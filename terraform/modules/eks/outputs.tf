# ==============================================================================
# EKS Module Outputs
# ==============================================================================
# Outputs for EKS cluster information.

output "cluster_id" {
  description = "EKS Cluster ID"
  value       = aws_eks_cluster.main.id
}

output "cluster_arn" {
  description = "EKS Cluster ARN"
  value       = aws_eks_cluster.main.arn
}

output "cluster_name" {
  description = "EKS Cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS Cluster API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority" {
  description = "EKS Cluster certificate authority data"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the cluster"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "cluster_oidc_provider_arn" {
  description = "ARN of the OIDC provider"
  value       = aws_iam_openid_connect_provider.oidc_provider.arn
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN used by the Kubernetes Cluster Autoscaler"
  value       = aws_iam_role.cluster_autoscaler.arn
}

output "node_group_id" {
  description = "EKS Node Group ID"
  value       = aws_eks_node_group.main.id
}

output "node_group_arn" {
  description = "EKS Node Group ARN"
  value       = aws_eks_node_group.main.arn
}

output "node_group_status" {
  description = "EKS Node Group status"
  value       = aws_eks_node_group.main.status
}

output "node_group_resources" {
  description = "List of node group resources"
  value       = aws_eks_node_group.main.resources
}

output "node_group_autoscaling_group_name" {
  description = "Auto Scaling Group name backing the managed node group"
  value       = aws_eks_node_group.main.resources[0].autoscaling_groups[0].name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for EKS"
  value       = var.enable_cloudwatch_logging ? aws_cloudwatch_log_group.eks_logs[0].arn : null
}

output "cluster_config_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --name ${var.cluster_name} --region ${data.aws_region.current.name}"
}
