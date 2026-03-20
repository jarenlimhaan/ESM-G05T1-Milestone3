# ==============================================================================
# Security Groups Module Outputs
# ==============================================================================
# Security Group IDs for use by other modules.

output "alb_sg_id" {
  description = "Security group ID for the internal ALB (backward compatibility)"
  value       = aws_security_group.internal_alb.id
}

output "public_alb_sg_id" {
  description = "Security group ID for the public ALB"
  value       = aws_security_group.public_alb.id
}

output "internal_alb_sg_id" {
  description = "Security group ID for the internal ALB"
  value       = aws_security_group.internal_alb.id
}

output "eks_cluster_sg_id" {
  description = "Security group ID for the EKS cluster"
  value       = aws_security_group.eks_cluster.id
}

output "eks_nodes_sg_id" {
  description = "Security group ID for EKS nodes"
  value       = aws_security_group.eks_nodes.id
}

output "odoo_rds_sg_id" {
  description = "Security group ID for Odoo RDS (PostgreSQL)"
  value       = aws_security_group.odoo_rds.id
}

output "moodle_rds_sg_id" {
  description = "Security group ID for Moodle RDS (MySQL)"
  value       = aws_security_group.moodle_rds.id
}

output "efs_sg_id" {
  description = "Security group ID for EFS"
  value       = aws_security_group.efs.id
}

output "vpn_sg_id" {
  description = "Security group ID for Client VPN"
  value       = aws_security_group.vpn.id
}

output "all_security_group_ids" {
  description = "Map of all security group IDs"
  value = {
    public_alb   = aws_security_group.public_alb.id
    internal_alb = aws_security_group.internal_alb.id
    eks_cluster  = aws_security_group.eks_cluster.id
    eks_nodes    = aws_security_group.eks_nodes.id
    odoo_rds     = aws_security_group.odoo_rds.id
    moodle_rds   = aws_security_group.moodle_rds.id
    efs          = aws_security_group.efs.id
    vpn          = aws_security_group.vpn.id
  }
}
