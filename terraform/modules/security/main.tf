# ==============================================================================
# Security Groups Module - Main Configuration
# ==============================================================================
# This module creates security groups following the principle of least privilege.
# Each security group allows only the necessary ports and protocols.

# ==============================================================================
# Public ALB Security Group
# ==============================================================================
# Allows inbound HTTP/HTTPS from public internet (or configured CIDRs)

resource "aws_security_group" "public_alb" {
  name_prefix = "${var.project_name}-${var.environment}-public-alb-"
  description = "Security group for the public Application Load Balancer"
  vpc_id      = var.vpc_id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-public-alb-sg"
    }
  )
}

# Allow HTTP from public CIDRs
resource "aws_vpc_security_group_ingress_rule" "public_alb_http" {
  for_each          = toset(var.public_alb_allowed_cidrs)
  security_group_id = aws_security_group.public_alb.id
  cidr_ipv4         = each.value
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
  description       = "Allow HTTP to public ALB"
}

# Allow HTTPS from public CIDRs
resource "aws_vpc_security_group_ingress_rule" "public_alb_https" {
  for_each          = toset(var.public_alb_allowed_cidrs)
  security_group_id = aws_security_group.public_alb.id
  cidr_ipv4         = each.value
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
  description       = "Allow HTTPS to public ALB"
}

# Allow outbound to EKS nodes for health checks
resource "aws_vpc_security_group_egress_rule" "public_alb_to_eks" {
  security_group_id = aws_security_group.public_alb.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 65535
  description       = "Allow outbound to EKS nodes"
}

# ==============================================================================
# Internal ALB Security Group
# ==============================================================================
# Allows inbound HTTP/HTTPS only from VPN clients

resource "aws_security_group" "internal_alb" {
  name_prefix = "${var.project_name}-${var.environment}-internal-alb-"
  description = "Security group for the internal Application Load Balancer"
  vpc_id      = var.vpc_id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-internal-alb-sg"
    }
  )
}

resource "aws_vpc_security_group_ingress_rule" "internal_alb_http_vpn" {
  security_group_id            = aws_security_group.internal_alb.id
  referenced_security_group_id = aws_security_group.vpn.id
  from_port                    = 80
  ip_protocol                  = "tcp"
  to_port                      = 80
  description                  = "Allow HTTP from VPN endpoint"
}

resource "aws_vpc_security_group_ingress_rule" "internal_alb_https_vpn" {
  security_group_id            = aws_security_group.internal_alb.id
  referenced_security_group_id = aws_security_group.vpn.id
  from_port                    = 443
  ip_protocol                  = "tcp"
  to_port                      = 443
  description                  = "Allow HTTPS from VPN endpoint"
}

resource "aws_vpc_security_group_egress_rule" "internal_alb_to_eks" {
  security_group_id = aws_security_group.internal_alb.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 65535
  description       = "Allow outbound to EKS nodes"
}

# ==============================================================================
# EKS Cluster Security Group
# ==============================================================================
# Allows communication between EKS control plane and worker nodes

resource "aws_security_group" "eks_cluster" {
  name_prefix = "${var.project_name}-${var.environment}-eks-cluster-"
  description = "Security group for the EKS cluster control plane"
  vpc_id      = var.vpc_id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-eks-cluster-sg"
    }
  )
}

# Allow inbound from EKS nodes (for communication with control plane)
resource "aws_vpc_security_group_ingress_rule" "eks_cluster_from_nodes" {
  security_group_id            = aws_security_group.eks_cluster.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  from_port                    = 443
  ip_protocol                  = "tcp"
  to_port                      = 443
  description                  = "Allow Kubernetes API server communication from nodes"
}

# Allow kubectl access to private EKS API from AWS Client VPN users.
resource "aws_vpc_security_group_ingress_rule" "eks_cluster_from_vpn" {
  security_group_id            = aws_security_group.eks_cluster.id
  referenced_security_group_id = aws_security_group.vpn.id
  from_port                    = 443
  ip_protocol                  = "tcp"
  to_port                      = 443
  description                  = "Allow Kubernetes API server communication from VPN endpoint"
}

# Allow outbound to EKS nodes
resource "aws_vpc_security_group_egress_rule" "eks_cluster_to_nodes" {
  security_group_id            = aws_security_group.eks_cluster.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  from_port                    = 1025
  ip_protocol                  = "tcp"
  to_port                      = 65535
  description                  = "Allow communication to nodes on all ports"
}

# ==============================================================================
# EKS Nodes Security Group
# ==============================================================================
# Allows communication from ALB, EKS cluster, and pod-to-pod communication

resource "aws_security_group" "eks_nodes" {
  name_prefix = "${var.project_name}-${var.environment}-eks-nodes-"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-eks-nodes-sg"
    }
  )
}

# Allow inbound from public ALB
resource "aws_vpc_security_group_ingress_rule" "eks_nodes_from_public_alb" {
  security_group_id            = aws_security_group.eks_nodes.id
  referenced_security_group_id = aws_security_group.public_alb.id
  from_port                    = 30000
  ip_protocol                  = "tcp"
  to_port                      = 32767
  description                  = "Allow NodePort services from public ALB"
}

# Allow inbound from internal ALB
resource "aws_vpc_security_group_ingress_rule" "eks_nodes_from_internal_alb" {
  security_group_id            = aws_security_group.eks_nodes.id
  referenced_security_group_id = aws_security_group.internal_alb.id
  from_port                    = 30000
  ip_protocol                  = "tcp"
  to_port                      = 32767
  description                  = "Allow NodePort services from internal ALB"
}

# Allow inbound from EKS cluster
resource "aws_vpc_security_group_ingress_rule" "eks_nodes_from_cluster" {
  security_group_id            = aws_security_group.eks_nodes.id
  referenced_security_group_id = aws_security_group.eks_cluster.id
  from_port                    = 1025
  ip_protocol                  = "tcp"
  to_port                      = 65535
  description                  = "Allow communication from EKS control plane"
}

# Allow pod-to-pod communication
resource "aws_vpc_security_group_ingress_rule" "eks_nodes_self" {
  security_group_id            = aws_security_group.eks_nodes.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  ip_protocol                  = "-1"
  description                  = "Allow intra-cluster communication"
}

# Allow outbound to anywhere (for pulling images, updates, etc.)
resource "aws_vpc_security_group_egress_rule" "eks_nodes_outbound" {
  security_group_id = aws_security_group.eks_nodes.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all outbound traffic"
}

# ==============================================================================
# Odoo RDS (PostgreSQL) Security Group
# ==============================================================================
# Allows PostgreSQL access only from EKS nodes

resource "aws_security_group" "odoo_rds" {
  name_prefix = "${var.project_name}-${var.environment}-odoo-rds-"
  description = "Security group for Odoo PostgreSQL RDS"
  vpc_id      = var.vpc_id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-odoo-rds-sg"
    }
  )
}

# Allow PostgreSQL from EKS nodes only
resource "aws_vpc_security_group_ingress_rule" "odoo_rds_from_eks" {
  security_group_id            = aws_security_group.odoo_rds.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  from_port                    = 5432
  ip_protocol                  = "tcp"
  to_port                      = 5432
  description                  = "Allow PostgreSQL from EKS nodes"
}

# ==============================================================================
# Moodle RDS (MySQL) Security Group
# ==============================================================================
# Allows MySQL access only from EKS nodes

resource "aws_security_group" "moodle_rds" {
  name_prefix = "${var.project_name}-${var.environment}-moodle-rds-"
  description = "Security group for Moodle MySQL RDS"
  vpc_id      = var.vpc_id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-moodle-rds-sg"
    }
  )
}

# Allow MySQL from EKS nodes only
resource "aws_vpc_security_group_ingress_rule" "moodle_rds_from_eks" {
  security_group_id            = aws_security_group.moodle_rds.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  from_port                    = 3306
  ip_protocol                  = "tcp"
  to_port                      = 3306
  description                  = "Allow MySQL from EKS nodes"
}

# ==============================================================================
# EFS Security Group
# ==============================================================================
# Allows NFS access from EKS nodes

resource "aws_security_group" "efs" {
  name_prefix = "${var.project_name}-${var.environment}-efs-"
  description = "Security group for EFS file system"
  vpc_id      = var.vpc_id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-efs-sg"
    }
  )
}

# Allow NFS (port 2049) from EKS nodes
resource "aws_vpc_security_group_ingress_rule" "efs_from_eks" {
  security_group_id            = aws_security_group.efs.id
  referenced_security_group_id = aws_security_group.eks_nodes.id
  from_port                    = 2049
  ip_protocol                  = "tcp"
  to_port                      = 2049
  description                  = "Allow NFS from EKS nodes"
}

# ==============================================================================
# VPN Security Group
# ==============================================================================
# Allows VPN clients to access internal services

resource "aws_security_group" "vpn" {
  name_prefix = "${var.project_name}-${var.environment}-vpn-"
  description = "Security group for Client VPN endpoint"
  vpc_id      = var.vpc_id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-vpn-sg"
    }
  )
}

# Allow all outbound from VPN
resource "aws_vpc_security_group_egress_rule" "vpn_outbound" {
  security_group_id = aws_security_group.vpn.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
  description       = "Allow VPN clients to access internal resources"
}
