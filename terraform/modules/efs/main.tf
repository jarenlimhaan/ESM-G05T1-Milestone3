# ==============================================================================
# EFS Module - Main Configuration
# ==============================================================================
# This module creates an EFS file system for persistent storage.
# Used by Odoo for storing file attachments, documents, and session data.

# ==============================================================================
# EFS File System
# ==============================================================================
# Creates a network file system that can be mounted by EKS pods

resource "aws_efs_file_system" "main" {
  creation_token   = "${var.project_name}-${var.environment}-efs"
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  # Automatic backups are enabled by default in AWS EFS
  # Backup and retention are managed through the AWS Backup module

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.project_name}-${var.environment}-efs"
      Application = "Odoo"
    }
  )
}

# Note: EFS lifecycle and automatic backups are configured through:
# - AWS Backup module handles scheduled backups
# - Lifecycle policies can be set via AWS EFS console if needed

# ==============================================================================
# Mount Targets
# ==============================================================================
# Create mount targets in each private application subnet
# These enable EKS pods to mount the EFS file system

resource "aws_efs_mount_target" "main" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [var.security_group_id]
}

# ==============================================================================
# EFS Access Point for Odoo
# ==============================================================================
# Creates an access point with a specific path and permissions
# This allows Odoo pods to mount only their designated directory

resource "aws_efs_access_point" "odoo" {
  file_system_id = aws_efs_file_system.main.id

  # POSIX user that owns the mount
  posix_user {
    uid = 1000
    gid = 1000
  }

  # Root directory permissions
  root_directory {
    path = "/odoo"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0755"
    }
  }

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.project_name}-${var.environment}-odoo-access-point"
      Application = "Odoo"
    }
  )
}

# ==============================================================================
# EFS Access Point for Moodle (Optional)
# ==============================================================================
# Create a separate access point for Moodle if needed for moodledata storage

resource "aws_efs_access_point" "moodle" {
  file_system_id = aws_efs_file_system.main.id

  # POSIX user that owns the mount
  posix_user {
    uid = 33 # www-data user
    gid = 33 # www-data group
  }

  # Root directory permissions
  root_directory {
    path = "/moodle"
    creation_info {
      owner_uid   = 33
      owner_gid   = 33
      permissions = "0755"
    }
  }

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.project_name}-${var.environment}-moodle-access-point"
      Application = "Moodle"
    }
  )
}
