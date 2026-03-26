#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/deploy-k8s-apps.sh \
    [--odoo-image "<image-ref>"] \
    [--odoo-db-password "<password>"] \
    [--moodle-db-password "<password>"] \
    [--osticket-db-password "<password>"] \
    [--odoo-secret-id "<aws-secretsmanager-id>"] \
    [--moodle-secret-id "<aws-secretsmanager-id>"] \
    [--osticket-secret-id "<aws-secretsmanager-id>"] \
    [--terraform-dir terraform] \
    [--aws-region ap-southeast-1] \
    [--odoo-db-user odoo_admin] \
    [--moodle-db-user moodle_admin] \
    [--moodle-db-name moodledb] \
    [--moodle-image "<image-ref>"] \
    [--moodle-admin-user admin] \
    [--moodle-admin-password "Admin~1234"] \
    [--moodle-admin-email "admin@esmos.meals.sg"] \
    [--moodle-url "http://moodle.internal.esm.local"] \
    [--osticket-db-host "<host>"] \
    [--osticket-db-user moodle_admin] \
    [--osticket-db-name osticketdb] \
    [--keep-rendered-manifests] \
    [--provision-infra]

Options:
  --odoo-db-password     Odoo password for secret/odoo-db.
  --odoo-image           Odoo container image (default: odoo:17.0).
  --moodle-db-password   Moodle password for secret/moodle-db.
  --osticket-db-password Optional. Password for secret/osticket-db.
                         Defaults to --moodle-db-password value.
  --odoo-secret-id       AWS Secrets Manager secret id for Odoo DB password.
  --moodle-secret-id     AWS Secrets Manager secret id for Moodle DB password.
  --osticket-secret-id   AWS Secrets Manager secret id for osTicket DB password.
                         If omitted, Moodle secret/password is reused.
  --terraform-dir        Terraform directory (default: terraform).
  --aws-region           AWS region. If omitted, read from Terraform output.
  --odoo-db-user         Odoo DB user (default: odoo_admin).
  --moodle-db-user       Moodle DB user (default: moodle_admin).
  --moodle-db-name       Moodle DB name (default: moodledb).
  --moodle-image         Moodle container image (default: ellakcy/moodle:mysql_maria_apache_latest).
  --moodle-admin-user    Moodle admin username (default: admin).
  --moodle-admin-password
                         Moodle admin password (default: Admin~1234).
  --moodle-admin-email   Moodle admin email (default: admin@esmos.meals.sg).
  --moodle-url           Moodle URL (default: http://moodle.internal.esm.local).
  --osticket-db-host     osTicket DB host. Defaults to Moodle DB host output.
  --osticket-db-user     osTicket DB user (default: moodle_admin).
  --osticket-db-name     osTicket DB name (default: osticketdb).
  --keep-rendered-manifests
                         Keep rendered temporary manifests for inspection.
  --provision-infra      Run terraform init + apply before kubectl apply.
  -h, --help             Show this help.
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' not found." >&2
    exit 1
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TERRAFORM_DIR="${REPO_ROOT}/terraform"
K8S_DIR="${REPO_ROOT}/k8s"
AWS_REGION=""
ODOO_DB_USER="odoo_admin"
ODOO_DB_PASSWORD=""
ODOO_IMAGE="odoo:17.0"
MOODLE_DB_USER="moodle_admin"
MOODLE_DB_PASSWORD=""
MOODLE_DB_NAME="moodledb"
MOODLE_IMAGE="ellakcy/moodle:mysql_maria_apache_latest"
MOODLE_ADMIN_USER="admin"
MOODLE_ADMIN_PASSWORD="Admin~1234"
MOODLE_ADMIN_EMAIL="admin@esmos.meals.sg"
MOODLE_URL="http://moodle.internal.esm.local"
OSTICKET_DB_HOST=""
OSTICKET_DB_USER="moodle_admin"
OSTICKET_DB_PASSWORD=""
OSTICKET_DB_NAME="osticketdb"
ODOO_SECRET_ID=""
MOODLE_SECRET_ID=""
OSTICKET_SECRET_ID=""
KEEP_RENDERED_MANIFESTS="false"
PROVISION_INFRA="false"
RENDER_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --terraform-dir)
      TERRAFORM_DIR="$2"
      shift 2
      ;;
    --aws-region)
      AWS_REGION="$2"
      shift 2
      ;;
    --odoo-db-user)
      ODOO_DB_USER="$2"
      shift 2
      ;;
    --odoo-db-password)
      ODOO_DB_PASSWORD="$2"
      shift 2
      ;;
    --odoo-image)
      ODOO_IMAGE="$2"
      shift 2
      ;;
    --moodle-db-user)
      MOODLE_DB_USER="$2"
      shift 2
      ;;
    --moodle-db-password)
      MOODLE_DB_PASSWORD="$2"
      shift 2
      ;;
    --moodle-db-name)
      MOODLE_DB_NAME="$2"
      shift 2
      ;;
    --moodle-image)
      MOODLE_IMAGE="$2"
      shift 2
      ;;
    --moodle-admin-user)
      MOODLE_ADMIN_USER="$2"
      shift 2
      ;;
    --moodle-admin-password)
      MOODLE_ADMIN_PASSWORD="$2"
      shift 2
      ;;
    --moodle-admin-email)
      MOODLE_ADMIN_EMAIL="$2"
      shift 2
      ;;
    --moodle-url)
      MOODLE_URL="$2"
      shift 2
      ;;
    --osticket-db-host)
      OSTICKET_DB_HOST="$2"
      shift 2
      ;;
    --osticket-db-user)
      OSTICKET_DB_USER="$2"
      shift 2
      ;;
    --osticket-db-password)
      OSTICKET_DB_PASSWORD="$2"
      shift 2
      ;;
    --osticket-db-name)
      OSTICKET_DB_NAME="$2"
      shift 2
      ;;
    --odoo-secret-id)
      ODOO_SECRET_ID="$2"
      shift 2
      ;;
    --moodle-secret-id)
      MOODLE_SECRET_ID="$2"
      shift 2
      ;;
    --osticket-secret-id)
      OSTICKET_SECRET_ID="$2"
      shift 2
      ;;
    --keep-rendered-manifests)
      KEEP_RENDERED_MANIFESTS="true"
      shift
      ;;
    --provision-infra)
      PROVISION_INFRA="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "${TERRAFORM_DIR}" != /* ]]; then
  TERRAFORM_DIR="${REPO_ROOT}/${TERRAFORM_DIR}"
fi

cleanup() {
  if [[ -n "${RENDER_DIR}" && -d "${RENDER_DIR}" && "${KEEP_RENDERED_MANIFESTS}" != "true" ]]; then
    rm -rf "${RENDER_DIR}"
  fi
}

trap cleanup EXIT

require_cmd terraform
require_cmd aws
require_cmd kubectl
require_cmd perl

if [[ "${PROVISION_INFRA}" == "true" ]]; then
  echo "Provisioning infrastructure with Terraform..."
  terraform -chdir="${TERRAFORM_DIR}" init
  terraform -chdir="${TERRAFORM_DIR}" apply -auto-approve
fi

echo "Reading Terraform outputs..."
CLUSTER_NAME="$(terraform -chdir="${TERRAFORM_DIR}" output -raw eks_cluster_name)"
CLUSTER_AUTOSCALER_ROLE_ARN="$(terraform -chdir="${TERRAFORM_DIR}" output -raw eks_cluster_autoscaler_role_arn)"
EKS_NODE_GROUP_ASG_NAME="$(terraform -chdir="${TERRAFORM_DIR}" output -raw eks_node_group_autoscaling_group_name)"
EKS_NODE_COUNT_MIN="$(terraform -chdir="${TERRAFORM_DIR}" output -raw eks_node_count_min)"
EKS_NODE_COUNT_MAX="$(terraform -chdir="${TERRAFORM_DIR}" output -raw eks_node_count_max)"
ODOO_DB_ENDPOINT="$(terraform -chdir="${TERRAFORM_DIR}" output -raw odoo_rds_endpoint)"
MOODLE_DB_ENDPOINT="$(terraform -chdir="${TERRAFORM_DIR}" output -raw moodle_rds_endpoint)"
ODOO_DB_NAME="$(terraform -chdir="${TERRAFORM_DIR}" output -raw odoo_db_name)"
EFS_ID="$(terraform -chdir="${TERRAFORM_DIR}" output -raw efs_id)"
EFS_ACCESS_POINT_ID="$(terraform -chdir="${TERRAFORM_DIR}" output -raw efs_odoo_access_point_id)"

ODOO_DB_HOST="${ODOO_DB_ENDPOINT%%:*}"
MOODLE_DB_HOST="${MOODLE_DB_ENDPOINT%%:*}"
if [[ -z "${OSTICKET_DB_HOST}" ]]; then
  OSTICKET_DB_HOST="${MOODLE_DB_HOST}"
fi

if [[ -z "${AWS_REGION}" ]]; then
  AWS_REGION="$(terraform -chdir="${TERRAFORM_DIR}" output -raw aws_region)"
fi

if [[ -n "${ODOO_SECRET_ID}" ]]; then
  ODOO_DB_PASSWORD="$(aws --region "${AWS_REGION}" secretsmanager get-secret-value --secret-id "${ODOO_SECRET_ID}" --query SecretString --output text)"
fi
if [[ -n "${MOODLE_SECRET_ID}" ]]; then
  MOODLE_DB_PASSWORD="$(aws --region "${AWS_REGION}" secretsmanager get-secret-value --secret-id "${MOODLE_SECRET_ID}" --query SecretString --output text)"
fi
if [[ -n "${OSTICKET_SECRET_ID}" ]]; then
  OSTICKET_DB_PASSWORD="$(aws --region "${AWS_REGION}" secretsmanager get-secret-value --secret-id "${OSTICKET_SECRET_ID}" --query SecretString --output text)"
fi

if [[ -z "${OSTICKET_DB_PASSWORD}" ]]; then
  OSTICKET_DB_PASSWORD="${MOODLE_DB_PASSWORD}"
fi

if [[ -z "${ODOO_DB_PASSWORD}" || -z "${MOODLE_DB_PASSWORD}" ]]; then
  echo "Error: provide passwords with --*-db-password or Secret IDs with --odoo-secret-id/--moodle-secret-id." >&2
  usage
  exit 1
fi

echo "Updating kubeconfig for cluster ${CLUSTER_NAME} in ${AWS_REGION}..."
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null

RENDER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/esm-k8s-XXXXXXXX")"
cp -R "${K8S_DIR}/." "${RENDER_DIR}/"

echo "Rendering manifests with current Terraform outputs..."
export ODOO_DB_HOST ODOO_DB_USER ODOO_DB_PASSWORD
export ODOO_DB_NAME
export ODOO_IMAGE
export MOODLE_DB_HOST MOODLE_DB_USER MOODLE_DB_NAME MOODLE_DB_PASSWORD
export MOODLE_IMAGE MOODLE_ADMIN_USER MOODLE_ADMIN_PASSWORD MOODLE_ADMIN_EMAIL MOODLE_URL
export OSTICKET_DB_HOST OSTICKET_DB_USER OSTICKET_DB_NAME OSTICKET_DB_PASSWORD
export EFS_ID EFS_ACCESS_POINT_ID
export CLUSTER_NAME CLUSTER_AUTOSCALER_ROLE_ARN EKS_NODE_GROUP_ASG_NAME
export EKS_NODE_COUNT_MIN EKS_NODE_COUNT_MAX

while IFS= read -r -d '' file; do
  perl -0777 -i -pe '
    s/__ODOO_DB_HOST__/$ENV{ODOO_DB_HOST}/g;
    s/__ODOO_DB_USER__/$ENV{ODOO_DB_USER}/g;
    s/__ODOO_DB_PASSWORD__/$ENV{ODOO_DB_PASSWORD}/g;
    s/__ODOO_DB_NAME__/$ENV{ODOO_DB_NAME}/g;
    s#__ODOO_IMAGE__#$ENV{ODOO_IMAGE}#g;
    s/__MOODLE_DB_HOST__/$ENV{MOODLE_DB_HOST}/g;
    s/__MOODLE_DB_USER__/$ENV{MOODLE_DB_USER}/g;
    s/__MOODLE_DB_NAME__/$ENV{MOODLE_DB_NAME}/g;
    s/__MOODLE_DB_PASSWORD__/$ENV{MOODLE_DB_PASSWORD}/g;
    s#__MOODLE_IMAGE__#$ENV{MOODLE_IMAGE}#g;
    s/__MOODLE_ADMIN_USER__/$ENV{MOODLE_ADMIN_USER}/g;
    s/__MOODLE_ADMIN_PASSWORD__/$ENV{MOODLE_ADMIN_PASSWORD}/g;
    s/__MOODLE_ADMIN_EMAIL__/$ENV{MOODLE_ADMIN_EMAIL}/g;
    s#__MOODLE_URL__#$ENV{MOODLE_URL}#g;
    s/__OSTICKET_DB_HOST__/$ENV{OSTICKET_DB_HOST}/g;
    s/__OSTICKET_DB_USER__/$ENV{OSTICKET_DB_USER}/g;
    s/__OSTICKET_DB_NAME__/$ENV{OSTICKET_DB_NAME}/g;
    s/__OSTICKET_DB_PASSWORD__/$ENV{OSTICKET_DB_PASSWORD}/g;
    s/__EFS_ID__/$ENV{EFS_ID}/g;
    s/__EFS_ACCESS_POINT_ID__/$ENV{EFS_ACCESS_POINT_ID}/g;
    s/__CLUSTER_NAME__/$ENV{CLUSTER_NAME}/g;
    s/__CLUSTER_AUTOSCALER_ROLE_ARN__/$ENV{CLUSTER_AUTOSCALER_ROLE_ARN}/g;
    s/__EKS_NODE_GROUP_ASG_NAME__/$ENV{EKS_NODE_GROUP_ASG_NAME}/g;
    s/__EKS_NODE_COUNT_MIN__/$ENV{EKS_NODE_COUNT_MIN}/g;
    s/__EKS_NODE_COUNT_MAX__/$ENV{EKS_NODE_COUNT_MAX}/g;
  ' "$file"
done < <(find "${RENDER_DIR}" -type f \( -name "*.yaml" -o -name "*.yml" \) -print0)

if grep -R --line-number "__[A-Z0-9_]\+__" "${RENDER_DIR}" >/dev/null; then
  echo "Error: unresolved placeholders found in rendered manifests." >&2
  grep -R --line-number "__[A-Z0-9_]\+__" "${RENDER_DIR}" >&2
  exit 1
fi

echo "Applying Kubernetes manifests..."
kubectl apply -k "${RENDER_DIR}"

echo "Restarting deployments..."
kubectl rollout restart deployment/odoo-private -n odoo-private
kubectl rollout restart deployment/odoo-private-gateway -n odoo-private
kubectl rollout restart deployment/odoo-public -n odoo-public
kubectl rollout restart deployment/moodle -n moodle-private
kubectl rollout restart deployment/osticket -n osticket-private
kubectl rollout status deployment/odoo-private -n odoo-private --timeout=300s
kubectl rollout status deployment/odoo-private-gateway -n odoo-private --timeout=300s
kubectl rollout status deployment/odoo-public -n odoo-public --timeout=300s
kubectl rollout status deployment/moodle -n moodle-private --timeout=300s
kubectl rollout status deployment/osticket -n osticket-private --timeout=300s

echo "Current pod status:"
kubectl get pods -n odoo-public
kubectl get pods -n odoo-private
kubectl get pods -n moodle-private
kubectl get pods -n osticket-private

if [[ "${KEEP_RENDERED_MANIFESTS}" == "true" ]]; then
  echo "Rendered manifests kept at: ${RENDER_DIR}"
fi

echo "Done."
