# ==============================================================================
# RDS Module - Main Configuration
# ==============================================================================
# This module creates RDS instances for:
# - Odoo: PostgreSQL database
# - Moodle: MySQL database
# Both are deployed in private subnets with no public access.

# ==============================================================================
# Subnet Group
# ==============================================================================
# A subnet group for RDS instances spanning private database subnets

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-db-subnet-group"
    }
  )
}

# ==============================================================================
# Parameter Groups
# ==============================================================================
# Custom parameter groups for optimal database performance

# PostgreSQL Parameter Group for Odoo
resource "aws_db_parameter_group" "odoo_postgres" {
  name   = "${var.project_name}-${var.environment}-odoo-postgres-pg"
  family = "postgres15"

  parameter {
    name         = "shared_buffers"
    value        = "{DBInstanceClassMemory/32}"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "max_connections"
    value        = "100"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = "5000" # Log slow queries (>5 seconds)
    apply_method = "pending-reboot"
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-odoo-postgres-pg"
    }
  )
}

# MySQL Parameter Group for Moodle
resource "aws_db_parameter_group" "moodle_mysql" {
  name   = "${var.project_name}-${var.environment}-moodle-mysql-pg"
  family = "mysql8.0"

  parameter {
    name  = "max_connections"
    value = "100"
  }

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "5"
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-moodle-mysql-pg"
    }
  )
}

# ==============================================================================
# Option Groups
# ==============================================================================
# Enable RDS Enhanced Monitoring (optional - requires IAM role)
# Uncomment if you want detailed performance metrics

/*
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-${var.environment}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
*/

# ==============================================================================
# Odoo PostgreSQL RDS Instance
# ==============================================================================
# PostgreSQL database for Odoo ERP system

resource "aws_db_instance" "odoo" {
  identifier            = "${var.project_name}-${var.environment}-odoo"
  engine                = "postgres"
  engine_version        = "15.17"
  instance_class        = var.odoo_instance_class
  allocated_storage     = 20
  max_allocated_storage = 100 # Enable autoscaling up to 100GB
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database configuration
  db_name  = var.odoo_db_name
  username = var.odoo_db_username
  password = var.odoo_db_password
  port     = 5432

  # Network configuration - PRIVATE ONLY
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.odoo_security_group_id]
  publicly_accessible    = false

  # High availability (optional - uncomment for Multi-AZ)
  # multi_az               = true

  # Backup configuration
  backup_retention_period   = var.backup_retention_period
  backup_window             = var.backup_window
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-${var.environment}-odoo-final-snapshot"

  # Maintenance
  maintenance_window         = var.maintenance_window
  auto_minor_version_upgrade = true

  # Performance
  parameter_group_name = aws_db_parameter_group.odoo_postgres.name

  # Monitoring
  monitoring_interval = 0 # Set to 0 unless a monitoring_role_arn is configured
  # monitoring_role_arn    = aws_iam_role.rds_monitoring.arn

  # Deletion protection
  deletion_protection = false # Set to true in production

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.project_name}-${var.environment}-odoo"
      Application = "Odoo"
    }
  )

  lifecycle {
    prevent_destroy = false # Set to true in production
  }
}

# ==============================================================================
# Moodle MySQL RDS Instance
# ==============================================================================
# MySQL database for Moodle LMS platform

resource "aws_db_instance" "moodle" {
  identifier            = "${var.project_name}-${var.environment}-moodle"
  engine                = "mysql"
  engine_version        = "8.0.45"
  instance_class        = var.moodle_instance_class
  allocated_storage     = 20
  max_allocated_storage = 100 # Enable autoscaling up to 100GB
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database configuration
  db_name  = var.moodle_db_name
  username = var.moodle_db_username
  password = var.moodle_db_password
  port     = 3306

  # Network configuration - PRIVATE ONLY
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.moodle_security_group_id]
  publicly_accessible    = false

  # High availability (optional - uncomment for Multi-AZ)
  # multi_az               = true

  # Backup configuration
  backup_retention_period   = var.backup_retention_period
  backup_window             = var.backup_window
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-${var.environment}-moodle-final-snapshot"

  # Maintenance
  maintenance_window         = var.maintenance_window
  auto_minor_version_upgrade = true

  # Performance
  parameter_group_name = aws_db_parameter_group.moodle_mysql.name

  # Monitoring
  monitoring_interval = 0

  # Deletion protection
  deletion_protection = false # Set to true in production

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.project_name}-${var.environment}-moodle"
      Application = "Moodle"
    }
  )

  lifecycle {
    prevent_destroy = false # Set to true in production
  }
}
