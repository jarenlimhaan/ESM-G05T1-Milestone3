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
    [--provision-infra]

Options:
  --odoo-db-password     Required. Password for secret/odoo-db.
  --moodle-db-password   Required. Password for secret/moodle-db.
  --terraform-dir        Terraform directory (default: terraform).
  --aws-region           AWS region. If omitted, read from Terraform output.
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
ODOO_DB_PASSWORD=""
MOODLE_DB_PASSWORD=""
PROVISION_INFRA="false"

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
    --odoo-db-password)
      ODOO_DB_PASSWORD="$2"
      shift 2
      ;;
    --moodle-db-password)
      MOODLE_DB_PASSWORD="$2"
      shift 2
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

require_cmd terraform
require_cmd aws
require_cmd kubectl

if [[ "${PROVISION_INFRA}" == "true" ]]; then
  echo "Provisioning infrastructure with Terraform..."
  terraform -chdir="${TERRAFORM_DIR}" init
  terraform -chdir="${TERRAFORM_DIR}" apply -auto-approve
fi

echo "Reading Terraform outputs..."
CLUSTER_NAME="$(terraform -chdir="${TERRAFORM_DIR}" output -raw eks_cluster_name)"
if [[ -z "${AWS_REGION}" ]]; then
  AWS_REGION="$(terraform -chdir="${TERRAFORM_DIR}" output -raw aws_region)"
fi

echo "Updating kubeconfig for cluster ${CLUSTER_NAME} in ${AWS_REGION}..."
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null

echo "Applying Kubernetes manifests..."
kubectl apply -k "${K8S_DIR}"

echo "Updating Kubernetes DB secrets..."
kubectl -n esm create secret generic odoo-db \
  --from-literal=password="${ODOO_DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n esm create secret generic moodle-db \
  --from-literal=password="${MOODLE_DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Restarting deployments to pick up secret values..."
kubectl rollout restart deployment/odoo -n esm
kubectl rollout restart deployment/moodle -n esm
kubectl rollout status deployment/odoo -n esm --timeout=300s
kubectl rollout status deployment/moodle -n esm --timeout=300s

echo "Current pod status:"
kubectl get pods -n esm

echo "Done."
