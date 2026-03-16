# ==============================================================================
# VPC Module - Main Configuration
# ==============================================================================
# This module creates a complete VPC networking setup with:
# - VPC
# - Internet Gateway
# - NAT Gateway (optional)
# - Public Subnets
# - Private Application Subnets
# - Private Database Subnets
# - Route Tables and Associations
# - VPC Flow Logs (optional)

# ==============================================================================
# Data Sources
# ==============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

# ==============================================================================
# VPC
# ==============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Enable Network ACL for additional security
  enable_network_address_usage_metrics = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-vpc"
    }
  )
}

# ==============================================================================
# Internet Gateway
# ==============================================================================
# Provides outbound internet access for public subnets

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-igw"
    }
  )
}

# ==============================================================================
# NAT Gateway
# ==============================================================================
# Provides outbound internet access for private subnets
# Deployed in public subnet to allow private resources to access external services

resource "aws_eip" "nat" {
  count  = var.single_nat_gateway ? 1 : length(var.availability_zones)
  domain = "vpc"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-nat-eip-${count.index}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count         = var.single_nat_gateway ? 1 : length(var.availability_zones)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-nat-${count.index}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# ==============================================================================
# Public Subnets
# ==============================================================================
# Subnets with direct internet access via Internet Gateway
# Used for NAT Gateway and potential public-facing resources

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-public-${count.index}"
      Type = "Public"
    }
  )
}

# ==============================================================================
# Private Application Subnets
# ==============================================================================
# Subnets for EKS nodes and application workloads
# No direct internet access, uses NAT Gateway for outbound

resource "aws_subnet" "private_app" {
  count             = length(var.private_app_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_app_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-private-app-${count.index}"
      Type = "Private-Application"
    }
  )
}

# ==============================================================================
# Private Database Subnets
# ==============================================================================
# Subnets for RDS instances
# Isolated from public internet, restricted database access

resource "aws_subnet" "private_db" {
  count             = length(var.private_db_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_db_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-private-db-${count.index}"
      Type = "Private-Database"
    }
  )
}

# Security group for interface VPC endpoints (HTTPS from within the VPC).
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.project_name}-${var.environment}-vpce-"
  description = "Security group for interface VPC endpoints"
  vpc_id      = aws_vpc.main.id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-vpce-sg"
    }
  )
}

resource "aws_vpc_security_group_ingress_rule" "vpce_https_from_vpc" {
  security_group_id = aws_security_group.vpc_endpoints.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "Allow HTTPS from VPC resources"
}

resource "aws_vpc_security_group_egress_rule" "vpce_all_outbound" {
  security_group_id = aws_security_group.vpc_endpoints.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow endpoint response traffic"
}

# ==============================================================================
# Route Table - Public
# ==============================================================================
# Routes public subnet traffic to Internet Gateway

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-public-rt"
    }
  )
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ==============================================================================
# Route Table - Private Application
# ==============================================================================
# Routes private app subnet traffic to NAT Gateway for outbound internet

resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[0].id
    }
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-private-app-rt"
    }
  )
}

resource "aws_route_table_association" "private_app" {
  count          = length(var.private_app_subnet_cidrs)
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app.id
}

# ==============================================================================
# Route Table - Private Database
# ==============================================================================
# Routes private db subnet traffic to NAT Gateway (for patching)
# Note: No inbound internet access for security

resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[0].id
    }
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-private-db-rt"
    }
  )
}

resource "aws_route_table_association" "private_db" {
  count          = length(var.private_db_subnet_cidrs)
  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db.id
}

# ==============================================================================
# VPC Endpoints
# ==============================================================================
# Private API endpoints reduce NAT dependence for EKS bootstrap and workloads.

locals {
  interface_vpc_endpoints = toset([
    "ec2",
    "ecr.api",
    "ecr.dkr",
    "logs",
    "sts",
    "ssm",
    "ec2messages",
    "ssmmessages"
  ])
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_vpc_endpoints

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-${replace(each.value, ".", "-")}-vpce"
    }
  )
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.aws_region}.s3"
  route_table_ids = [
    aws_route_table.private_app.id,
    aws_route_table.private_db.id
  ]
  vpc_endpoint_type = "Gateway"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-s3-endpoint"
    }
  )
}

# ==============================================================================
# DHCP Options (Optional - custom DNS)
# ==============================================================================
# Uncomment if you need custom DNS configuration

/*
resource "aws_vpc_dhcp_options" "main" {
  domain_name_servers = ["AmazonProvidedDNS"]

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-dhcp-options"
    }
  )
}

resource "aws_vpc_dhcp_options_association" "main" {
  vpc_id          = aws_vpc.main.id
  dhcp_options_id = aws_vpc_dhcp_options.main.id
}
*/
