locals {
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
    },
    var.additional_tags
  )

  project_prefix = "${var.project_name}-${var.environment}"

  has_public_zone_name  = trimspace(var.public_route53_zone_name) != ""
  has_private_zone_name = trimspace(var.private_route53_zone_name) != ""

  use_public_host_routing   = var.create_public_route53_zone && local.has_public_zone_name
  use_internal_host_routing = var.create_private_route53_zone && local.has_private_zone_name

  odoo_public_fqdn = "${var.odoo_public_record_name}.${var.public_route53_zone_name}"

  odoo_internal_fqdn     = "${var.odoo_internal_record_name}.${var.private_route53_zone_name}"
  moodle_internal_fqdn   = "${var.moodle_internal_record_name}.${var.private_route53_zone_name}"
  osticket_internal_fqdn = "${var.osticket_internal_record_name}.${var.private_route53_zone_name}"
}

data "terraform_remote_state" "lz0" {
  backend = "s3"

  config = {
    bucket = var.state_bucket_name
    key    = var.lz0_state_key
    region = var.state_region
  }
}

data "terraform_remote_state" "lz1" {
  backend = "s3"

  config = {
    bucket = var.state_bucket_name
    key    = var.lz1_state_key
    region = var.state_region
  }
}

resource "aws_secretsmanager_secret" "odoo_db_password" {
  name                    = var.odoo_db_password_secret_id
  recovery_window_in_days = 0
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "odoo_db_password" {
  secret_id     = aws_secretsmanager_secret.odoo_db_password.id
  secret_string = var.odoo_db_password
}

resource "aws_secretsmanager_secret" "moodle_db_password" {
  name                    = var.moodle_db_password_secret_id
  recovery_window_in_days = 0
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "moodle_db_password" {
  secret_id     = aws_secretsmanager_secret.moodle_db_password.id
  secret_string = var.moodle_db_password
}

# osTicket DB password — osTicket shares the same MySQL RDS instance as Moodle.
# Both apps connect with the same master credentials (moodle_db_password).
# No separate secret is required; the osticket IRSA role is granted access
# to moodle_db_password so the CSI driver fetches the correct credential.

resource "aws_secretsmanager_secret" "moodle_admin_password" {
  name                    = var.moodle_admin_password_secret_id
  recovery_window_in_days = 0
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "moodle_admin_password" {
  secret_id     = aws_secretsmanager_secret.moodle_admin_password.id
  secret_string = var.moodle_admin_password
}

resource "aws_secretsmanager_secret" "osticket_install_secret" {
  name                    = var.osticket_install_secret_id
  recovery_window_in_days = 0
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "osticket_install_secret" {
  secret_id     = aws_secretsmanager_secret.osticket_install_secret.id
  secret_string = var.osticket_install_secret
}

resource "aws_secretsmanager_secret" "osticket_admin_password" {
  name                    = var.osticket_admin_password_secret_id
  recovery_window_in_days = 0
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "osticket_admin_password" {
  secret_id     = aws_secretsmanager_secret.osticket_admin_password.id
  secret_string = var.osticket_admin_password
}

locals {
  odoo_db_password_resolved   = aws_secretsmanager_secret_version.odoo_db_password.secret_string
  moodle_db_password_resolved = aws_secretsmanager_secret_version.moodle_db_password.secret_string

  # OIDC issuer without the https:// prefix — used as the condition key prefix
  # in IRSA trust policies (IAM condition keys use the bare hostname, not a URL)
  oidc_issuer = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
}

module "rds" {
  source = "../modules/rds"

  project_name = var.project_name
  environment  = var.environment

  vpc_id             = data.terraform_remote_state.lz1.outputs.vpc_id
  availability_zones = var.availability_zones
  private_subnet_ids = data.terraform_remote_state.lz1.outputs.private_db_subnet_ids

  odoo_security_group_id   = data.terraform_remote_state.lz1.outputs.security_group_ids.odoo_rds
  moodle_security_group_id = data.terraform_remote_state.lz1.outputs.security_group_ids.moodle_rds

  odoo_db_name        = var.odoo_db_name
  odoo_db_username    = var.odoo_db_username
  odoo_db_password    = local.odoo_db_password_resolved
  odoo_instance_class = var.db_instance_class

  moodle_db_name        = var.moodle_db_name
  moodle_db_username    = var.moodle_db_username
  moodle_db_password    = local.moodle_db_password_resolved
  moodle_instance_class = var.db_instance_class

  backup_retention_period           = var.backup_retention_days
  automated_backup_retention_period = var.rds_automated_backup_retention_period
  skip_final_snapshot               = var.rds_skip_final_snapshot

  common_tags = local.common_tags
}

module "efs" {
  source = "../modules/efs"

  project_name = var.project_name
  environment  = var.environment

  vpc_id             = data.terraform_remote_state.lz1.outputs.vpc_id
  availability_zones = var.availability_zones
  private_subnet_ids = data.terraform_remote_state.lz1.outputs.private_app_subnet_ids

  security_group_id = data.terraform_remote_state.lz1.outputs.security_group_ids.efs

  common_tags = local.common_tags
}

module "backup" {
  source = "../modules/backup"

  project_name = var.project_name
  environment  = var.environment

  odoo_rds_arn   = module.rds.odoo_instance_arn
  moodle_rds_arn = module.rds.moodle_instance_arn
  efs_arn        = module.efs.efs_arn

  backup_retention_days = var.backup_retention_days

  common_tags = local.common_tags

  depends_on = [
    module.rds,
    module.efs
  ]
}

module "eks" {
  source = "../modules/eks"

  project_name = var.project_name
  environment  = var.environment

  cluster_version = var.eks_cluster_version
  cluster_name    = "${local.project_prefix}-eks"

  vpc_id             = data.terraform_remote_state.lz1.outputs.vpc_id
  availability_zones = var.availability_zones
  private_subnet_ids = data.terraform_remote_state.lz1.outputs.private_app_subnet_ids

  cluster_security_group_id = data.terraform_remote_state.lz1.outputs.security_group_ids.eks_cluster
  nodes_security_group_id   = data.terraform_remote_state.lz1.outputs.security_group_ids.eks_nodes

  node_instance_type = var.eks_node_instance_type
  node_count_min     = var.eks_node_count_min
  node_count_max     = var.eks_node_count_max
  node_count_desired = var.eks_node_count_desired

  enable_cloudwatch_logging = var.enable_monitoring

  common_tags = local.common_tags
}

module "alb_public" {
  source = "../modules/alb"

  project_name = var.project_name
  environment  = var.environment

  vpc_id     = data.terraform_remote_state.lz1.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.lz1.outputs.public_subnet_ids

  alb_security_group_id = data.terraform_remote_state.lz1.outputs.security_group_ids.public_alb

  internal            = false
  alb_name_suffix     = "public"
  node_group_asg_name = module.eks.node_group_autoscaling_group_name
  odoo_node_port      = 30080
  odoo_path_patterns  = ["/*"]
  odoo_host_headers   = local.use_public_host_routing ? [local.odoo_public_fqdn] : []
  enable_odoo         = true
  enable_moodle       = false
  enable_osticket     = false

  certificate_arn = var.alb_certificate_arn

  common_tags = local.common_tags

  depends_on = [module.eks]
}

module "alb_internal" {
  source = "../modules/alb"

  project_name = var.project_name
  environment  = var.environment

  vpc_id     = data.terraform_remote_state.lz1.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.lz1.outputs.private_app_subnet_ids

  alb_security_group_id = data.terraform_remote_state.lz1.outputs.security_group_ids.internal_alb

  internal               = true
  alb_name_suffix        = "internal"
  node_group_asg_name    = module.eks.node_group_autoscaling_group_name
  odoo_node_port         = 30081
  odoo_path_patterns     = local.use_internal_host_routing ? ["/*"] : ["/odoo*", "/web*"]
  odoo_host_headers      = local.use_internal_host_routing ? [local.odoo_internal_fqdn] : []
  moodle_node_port       = 30082
  moodle_path_patterns   = local.use_internal_host_routing ? ["/*"] : ["/moodle*"]
  moodle_host_headers    = local.use_internal_host_routing ? [local.moodle_internal_fqdn] : []
  osticket_node_port     = 30083
  osticket_path_patterns = local.use_internal_host_routing ? ["/*"] : ["/osticket*"]
  osticket_host_headers  = local.use_internal_host_routing ? [local.osticket_internal_fqdn] : []
  enable_odoo            = true
  enable_moodle          = true
  enable_osticket        = true

  certificate_arn = var.alb_certificate_arn

  common_tags = local.common_tags

  depends_on = [module.eks]
}

module "waf" {
  source = "../modules/waf"

  project_name = var.project_name
  environment  = var.environment

  enable_waf     = var.enable_waf
  waf_rate_limit = var.waf_rate_limit
  alb_public_arn = module.alb_public.alb_arn
  common_tags    = local.common_tags

  depends_on = [module.alb_public]
}

module "dns" {
  source = "../modules/dns"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = data.terraform_remote_state.lz1.outputs.vpc_id

  create_public_zone  = var.create_public_route53_zone
  public_zone_name    = var.public_route53_zone_name
  create_private_zone = var.create_private_route53_zone
  private_zone_name   = var.private_route53_zone_name

  odoo_public_record_name       = var.odoo_public_record_name
  odoo_internal_record_name     = var.odoo_internal_record_name
  moodle_internal_record_name   = var.moodle_internal_record_name
  osticket_internal_record_name = var.osticket_internal_record_name

  public_alb_dns_name   = module.alb_public.alb_dns_name
  public_alb_zone_id    = module.alb_public.alb_zone_id
  internal_alb_dns_name = module.alb_internal.alb_dns_name
  internal_alb_zone_id  = module.alb_internal.alb_zone_id

  common_tags = local.common_tags

  depends_on = [module.alb_public, module.alb_internal]
}

module "monitoring" {
  source = "../modules/monitoring"

  project_name = var.project_name
  environment  = var.environment

  alert_email = var.alert_email

  odoo_rds_id                             = split(".", module.rds.odoo_endpoint)[0]
  moodle_rds_id                           = split(".", module.rds.moodle_endpoint)[0]
  efs_id                                  = module.efs.efs_id
  eks_cluster_name                        = module.eks.cluster_name
  moodle_namespace                        = "moodle-private"
  moodle_pod_cpu_threshold                = 80
  moodle_pod_memory_threshold             = 80
  odoo_namespaces                         = ["odoo-public", "odoo-private"]
  odoo_pod_cpu_threshold                  = 70
  monitored_namespaces                    = ["odoo-public", "odoo-private", "moodle-private", "osticket-private"]
  pod_restart_threshold                   = 3
  alb_5xx_rate_threshold_percent          = 1
  public_alb_arn_suffix                   = module.alb_public.alb_arn_suffix
  internal_alb_arn_suffix                 = module.alb_internal.alb_arn_suffix
  public_odoo_target_group_arn_suffix     = module.alb_public.target_group_arn_suffix_odoo
  internal_moodle_target_group_arn_suffix = module.alb_internal.target_group_arn_suffix_moodle
  eks_node_cpu_threshold                  = 85
  eks_node_memory_threshold               = 85
  monthly_budget_limit_usd                = var.monthly_budget_limit_usd

  enable_monitoring = var.enable_monitoring

  common_tags = local.common_tags
}

data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = try(module.eks.cluster_endpoint, "https://localhost")
  cluster_ca_certificate = try(base64decode(module.eks.cluster_certificate_authority), "")
  token                  = try(data.aws_eks_cluster_auth.main.token, "")
}

resource "kubernetes_namespace" "odoo_public" {
  metadata {
    name   = "odoo-public"
    labels = { "app.kubernetes.io/part-of" = "esm" }
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "odoo_private" {
  metadata {
    name   = "odoo-private"
    labels = { "app.kubernetes.io/part-of" = "esm" }
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "moodle_private" {
  metadata {
    name   = "moodle-private"
    labels = { "app.kubernetes.io/part-of" = "esm" }
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "osticket_private" {
  metadata {
    name   = "osticket-private"
    labels = { "app.kubernetes.io/part-of" = "esm" }
  }

  depends_on = [module.eks]
}

resource "kubernetes_secret" "odoo_db_odoo_public" {
  metadata {
    name      = "odoo-db"
    namespace = kubernetes_namespace.odoo_public.metadata[0].name
  }

  data = {
    password = aws_secretsmanager_secret_version.odoo_db_password.secret_string
  }
}

resource "kubernetes_secret" "odoo_db_odoo_private" {
  metadata {
    name      = "odoo-db"
    namespace = kubernetes_namespace.odoo_private.metadata[0].name
  }

  data = {
    password = aws_secretsmanager_secret_version.odoo_db_password.secret_string
  }
}

resource "kubernetes_secret" "moodle_db" {
  metadata {
    name      = "moodle-db"
    namespace = kubernetes_namespace.moodle_private.metadata[0].name
  }

  data = {
    password       = aws_secretsmanager_secret_version.moodle_db_password.secret_string
    admin_password = var.moodle_admin_password
  }
}

resource "kubernetes_secret" "osticket_db" {
  metadata {
    name      = "osticket-db"
    namespace = kubernetes_namespace.osticket_private.metadata[0].name
  }

  data = {
    # osTicket shares the Moodle MySQL RDS instance — use the same master credential.
    password       = aws_secretsmanager_secret_version.moodle_db_password.secret_string
    install_secret = var.osticket_install_secret
    admin_password = var.osticket_admin_password
  }
}

# ==============================================================================
# IRSA — IAM Roles for Service Accounts
# ==============================================================================
# Each application workload gets its own IAM role bound to its Kubernetes
# service account via the EKS OIDC provider. Pods exchange their projected
# service account JWT for temporary AWS STS credentials, which are then used
# by the Secrets Store CSI Driver (ASCP) to call secretsmanager:GetSecretValue.
#
# Trust policy conditions:
#   :aud — ensures the token was projected for AWS STS, not the Kubernetes API
#   :sub — scopes the role to one specific service account in one namespace

# ------------------------------------------------------------------------------
# Odoo Private
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "irsa_odoo_private_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.cluster_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:odoo-private:odoo-private"]
    }
  }
}

resource "aws_iam_role" "odoo_private" {
  name               = "${local.project_prefix}-odoo-private-irsa"
  assume_role_policy = data.aws_iam_policy_document.irsa_odoo_private_trust.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "odoo_private_secrets" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_secretsmanager_secret.odoo_db_password.arn]
  }
}

resource "aws_iam_policy" "odoo_private_secrets" {
  name   = "${local.project_prefix}-odoo-private-secrets"
  policy = data.aws_iam_policy_document.odoo_private_secrets.json
  tags   = local.common_tags
}

resource "aws_iam_role_policy_attachment" "odoo_private_secrets" {
  role       = aws_iam_role.odoo_private.name
  policy_arn = aws_iam_policy.odoo_private_secrets.arn
}

# ------------------------------------------------------------------------------
# Odoo Public
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "irsa_odoo_public_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.cluster_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:odoo-public:odoo-public"]
    }
  }
}

resource "aws_iam_role" "odoo_public" {
  name               = "${local.project_prefix}-odoo-public-irsa"
  assume_role_policy = data.aws_iam_policy_document.irsa_odoo_public_trust.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "odoo_public_secrets" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_secretsmanager_secret.odoo_db_password.arn]
  }
}

resource "aws_iam_policy" "odoo_public_secrets" {
  name   = "${local.project_prefix}-odoo-public-secrets"
  policy = data.aws_iam_policy_document.odoo_public_secrets.json
  tags   = local.common_tags
}

resource "aws_iam_role_policy_attachment" "odoo_public_secrets" {
  role       = aws_iam_role.odoo_public.name
  policy_arn = aws_iam_policy.odoo_public_secrets.arn
}

# ------------------------------------------------------------------------------
# Moodle
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "irsa_moodle_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.cluster_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:moodle-private:moodle"]
    }
  }
}

resource "aws_iam_role" "moodle" {
  name               = "${local.project_prefix}-moodle-irsa"
  assume_role_policy = data.aws_iam_policy_document.irsa_moodle_trust.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "moodle_secrets" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [
      aws_secretsmanager_secret.moodle_db_password.arn,
      aws_secretsmanager_secret.moodle_admin_password.arn,
    ]
  }
}

resource "aws_iam_policy" "moodle_secrets" {
  name   = "${local.project_prefix}-moodle-secrets"
  policy = data.aws_iam_policy_document.moodle_secrets.json
  tags   = local.common_tags
}

resource "aws_iam_role_policy_attachment" "moodle_secrets" {
  role       = aws_iam_role.moodle.name
  policy_arn = aws_iam_policy.moodle_secrets.arn
}

# ------------------------------------------------------------------------------
# osTicket
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "irsa_osticket_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.cluster_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:osticket-private:osticket"]
    }
  }
}

resource "aws_iam_role" "osticket" {
  name               = "${local.project_prefix}-osticket-irsa"
  assume_role_policy = data.aws_iam_policy_document.irsa_osticket_trust.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "osticket_secrets" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [
      # DB password: osTicket shares the Moodle MySQL RDS — use moodle_db_password secret.
      aws_secretsmanager_secret.moodle_db_password.arn,
      aws_secretsmanager_secret.osticket_install_secret.arn,
      aws_secretsmanager_secret.osticket_admin_password.arn,
    ]
  }
}

resource "aws_iam_policy" "osticket_secrets" {
  name   = "${local.project_prefix}-osticket-secrets"
  policy = data.aws_iam_policy_document.osticket_secrets.json
  tags   = local.common_tags
}

resource "aws_iam_role_policy_attachment" "osticket_secrets" {
  role       = aws_iam_role.osticket.name
  policy_arn = aws_iam_policy.osticket_secrets.arn
}
