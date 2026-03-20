#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/deploy-k8s-apps.sh \
    --odoo-db-password "<password>" \
    --moodle-db-password "<password>" \
    [--terraform-dir terraform] \
    [--aws-region ap-southeast-1] \
    [--odoo-db-user odoo_admin] \
    [--moodle-db-user moodle_admin] \
    [--moodle-db-name moodledb] \
    [--keep-rendered-manifests] \
    [--provision-infra]

Options:
  --odoo-db-password     Required. Password for secret/odoo-db.
  --moodle-db-password   Required. Password for secret/moodle-db.
  --terraform-dir        Terraform directory (default: terraform).
  --aws-region           AWS region. If omitted, read from Terraform output.
  --odoo-db-user         Odoo DB user (default: odoo_admin).
  --moodle-db-user       Moodle DB user (default: moodle_admin).
  --moodle-db-name       Moodle DB name (default: moodledb).
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
MOODLE_DB_USER="moodle_admin"
MOODLE_DB_PASSWORD=""
MOODLE_DB_NAME="moodledb"
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

if [[ -z "${ODOO_DB_PASSWORD}" || -z "${MOODLE_DB_PASSWORD}" ]]; then
  echo "Error: --odoo-db-password and --moodle-db-password are required." >&2
  usage
  exit 1
fi

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

if [[ -z "${AWS_REGION}" ]]; then
  AWS_REGION="$(terraform -chdir="${TERRAFORM_DIR}" output -raw aws_region)"
fi

echo "Updating kubeconfig for cluster ${CLUSTER_NAME} in ${AWS_REGION}..."
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null

RENDER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/esm-k8s-XXXXXXXX")"
cp -R "${K8S_DIR}/." "${RENDER_DIR}/"

echo "Rendering manifests with current Terraform outputs..."
export ODOO_DB_HOST ODOO_DB_USER ODOO_DB_PASSWORD
export ODOO_DB_NAME
export MOODLE_DB_HOST MOODLE_DB_USER MOODLE_DB_NAME MOODLE_DB_PASSWORD
export EFS_ID EFS_ACCESS_POINT_ID
export CLUSTER_NAME CLUSTER_AUTOSCALER_ROLE_ARN EKS_NODE_GROUP_ASG_NAME
export EKS_NODE_COUNT_MIN EKS_NODE_COUNT_MAX

while IFS= read -r -d '' file; do
  perl -0777 -i -pe '
    s/__ODOO_DB_HOST__/$ENV{ODOO_DB_HOST}/g;
    s/__ODOO_DB_USER__/$ENV{ODOO_DB_USER}/g;
    s/__ODOO_DB_PASSWORD__/$ENV{ODOO_DB_PASSWORD}/g;
    s/__ODOO_DB_NAME__/$ENV{ODOO_DB_NAME}/g;
    s/__MOODLE_DB_HOST__/$ENV{MOODLE_DB_HOST}/g;
    s/__MOODLE_DB_USER__/$ENV{MOODLE_DB_USER}/g;
    s/__MOODLE_DB_NAME__/$ENV{MOODLE_DB_NAME}/g;
    s/__MOODLE_DB_PASSWORD__/$ENV{MOODLE_DB_PASSWORD}/g;
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

echo "Removing retired services (moodle-public)..."
kubectl delete svc moodle-public -n esm --ignore-not-found

echo "Restarting deployments..."
kubectl rollout restart deployment/odoo-private -n esm
kubectl rollout restart deployment/odoo-public -n esm
kubectl rollout restart deployment/moodle -n esm
kubectl rollout status deployment/odoo-private -n esm --timeout=300s
kubectl rollout status deployment/odoo-public -n esm --timeout=300s
kubectl rollout status deployment/moodle -n esm --timeout=300s

echo "Current pod status:"
kubectl get pods -n esm

if [[ "${KEEP_RENDERED_MANIFESTS}" == "true" ]]; then
  echo "Rendered manifests kept at: ${RENDER_DIR}"
fi

echo "Done."
