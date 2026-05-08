# ==============================================================================
# EKS Module - Main Configuration
# ==============================================================================
# This module creates an EKS cluster with managed node group.
# The cluster is deployed in private subnets for security.

# ==============================================================================
# Data Sources
# ==============================================================================

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.main.name
}

# ==============================================================================
# CloudWatch Log Group for EKS
# ==============================================================================
# Centralized logging for EKS control plane and workloads

resource "aws_cloudwatch_log_group" "eks_logs" {
  count             = var.enable_cloudwatch_logging ? 1 : 0
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.enable_cloudwatch_logging ? 7 : null

  tags = merge(
    var.common_tags,
    {
      Name = "${var.cluster_name}-logs"
    }
  )
}

# ==============================================================================
# IAM Role for EKS Cluster
# ==============================================================================
# IAM role with permissions for EKS cluster to manage resources

resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

# Attach AmazonEKSClusterPolicy
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# Attach AmazonEKSVPCResourceController (for ENI management)
resource "aws_iam_role_policy_attachment" "eks_vpc_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

# ==============================================================================
# EKS Cluster
# ==============================================================================
# The managed Kubernetes control plane

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.cluster_version

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # VPC Configuration
  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [var.cluster_security_group_id]
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  # Logging Configuration
  enabled_cluster_log_types = var.enable_cloudwatch_logging ? [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ] : []

  # KMS encryption (optional - uncomment to enable)
  # encryption_config {
  #   provider {
  #     key_arn = aws_kms_key.eks.arn
  #   }
  #   resources = ["secrets"]
  # }

  # Kubernetes network configuration
  kubernetes_network_config {
    service_ipv4_cidr = "10.100.64.0/18" # Pod CIDR (must not overlap with VPC)
    ip_family         = "ipv4"
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-eks"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_controller,
    aws_cloudwatch_log_group.eks_logs
  ]
}

# Launch template pins the worker-node security group so RDS/EFS SG rules
# that reference var.nodes_security_group_id are actually enforced.
resource "aws_launch_template" "eks_nodes" {
  name_prefix = "${var.project_name}-${var.environment}-eks-nodes-"

  vpc_security_group_ids = [var.nodes_security_group_id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 50
      volume_type = "gp3"
      encrypted   = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.common_tags,
      {
        Name = "${var.project_name}-${var.environment}-node"
      }
    )
  }
}

# ==============================================================================
# OIDC Provider for EKS
# ==============================================================================
# Enables IAM roles for Kubernetes service accounts (IRSA)

resource "aws_iam_openid_connect_provider" "oidc_provider" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

data "tls_certificate" "oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# ==============================================================================
# IAM Role for EKS Node Group
# ==============================================================================
# IAM role with permissions for worker nodes

resource "aws_iam_role" "eks_nodes" {
  name = "${var.project_name}-${var.environment}-eks-nodes-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

# Attach AmazonEKSWorkerNodePolicy
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

# Attach AmazonEKS_CNI_Policy (for AWS VPC CNI)
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

# Attach AmazonEC2ContainerRegistryReadOnly
resource "aws_iam_role_policy_attachment" "eks_ecr_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

# Attach CloudWatch Agent policy for node metrics
resource "aws_iam_role_policy_attachment" "eks_cloudwatch_policy" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.eks_nodes.name
}

# ==============================================================================
# IAM Role for Cluster Autoscaler
# ==============================================================================
# Allows the Kubernetes Cluster Autoscaler to scale the managed node group's
# backing Auto Scaling Group via IAM Roles for Service Accounts.

resource "aws_iam_role" "cluster_autoscaler" {
  name = "${var.project_name}-${var.environment}-cluster-autoscaler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.oidc_provider.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.oidc_provider.url, "https://", "")}:aud" = "sts.amazonaws.com"
            "${replace(aws_iam_openid_connect_provider.oidc_provider.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
          }
        }
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name = "${var.project_name}-${var.environment}-cluster-autoscaler-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:DescribeTags",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}

# ==============================================================================
# EKS Node Group
# ==============================================================================
# Managed node group for running application workloads

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-${var.environment}-node-group"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  version         = var.cluster_version

  # Subnet configuration - deploy in private subnets only
  subnet_ids = var.private_subnet_ids

  # Node configuration
  instance_types = [var.node_instance_type]
  capacity_type  = "ON_DEMAND"
  ami_type       = "AL2023_x86_64_STANDARD"

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = aws_launch_template.eks_nodes.latest_version
  }

  # Scaling configuration
  scaling_config {
    desired_size = var.node_count_desired
    max_size     = var.node_count_max
    min_size     = var.node_count_min
  }

  # Node labels and taints
  labels = {
    "esm/node-role"    = "worker"
    "esm/workload"     = "applications"
    "esm/applications" = "odoo-moodle"
  }

  # Update configuration
  update_config {
    max_unavailable_percentage = 33 # Allow rolling updates
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-node"
    }
  )

  # Ensure the cluster exists before creating node group
  depends_on = [
    aws_launch_template.eks_nodes,
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_policy,
    aws_iam_role_policy_attachment.eks_cloudwatch_policy
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ==============================================================================
# Kubernetes ConfigMap for aws-auth
# ==============================================================================
# (Optional) Custom aws-auth configmap if needed
# This is typically managed by EKS, but can be customized here

# ==============================================================================
# EBS CSI Driver Addon
# ==============================================================================
# Enable EBS CSI driver for dynamic volume provisioning (optional)

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = "v1.32.0-eksbuild.1" # Update based on cluster version
  service_account_role_arn    = aws_iam_role.ebs_csi_driver.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.common_tags

  depends_on = [
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.ebs_csi_driver_policy
  ]
}

resource "aws_iam_role" "ebs_csi_driver" {
  name = "${var.project_name}-${var.environment}-ebs-csi-driver-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.oidc_provider.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.oidc_provider.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_driver.name
}

# ==============================================================================
# EFS CSI Driver Addon
# ==============================================================================
# Enable EFS CSI driver for mounting EFS file systems

resource "aws_eks_addon" "efs_csi_driver" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "aws-efs-csi-driver"
  addon_version               = "v2.0.2-eksbuild.1" # Update based on cluster version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.common_tags

  depends_on = [
    aws_eks_node_group.main
  ]
}
