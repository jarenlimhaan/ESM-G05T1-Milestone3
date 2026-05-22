#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Apply landing zone layers in order: lz0 -> lz1 -> lz2.

Usage:
  ./scripts/apply-landing-zones.sh \
    [--terraform-root terraform] \
    [--lz0-dir lz0-storage] \
    [--lz1-dir lz1-network] \
    [--lz2-dir lz2-orchestration] \
    [--aws-region ap-southeast-1] \
    --odoo-db-password "..." \
    --moodle-db-password "..." \
    --osticket-db-password "..." \
    --osticket-install-secret "..." \
    --osticket-admin-password "..." \
    [--skip-k8s-apps] \
    [--skip-bootstrap]

Options:
  --skip-k8s-apps  Only provision Terraform landing zones. Do not apply Kubernetes app manifests.
  --skip-bootstrap Only provision Terraform and apply Kubernetes manifests. Do not restore/bootstrap app data.
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

TF_ROOT="${REPO_ROOT}/terraform"
LZ0_DIR="lz0-storage"
LZ1_DIR="lz1-network"
LZ2_DIR="lz2-orchestration"
AWS_REGION="ap-southeast-1"
SKIP_K8S_APPS="false"
SKIP_BOOTSTRAP="false"

ODOO_DB_PASSWORD=""
MOODLE_DB_PASSWORD=""
OSTICKET_DB_PASSWORD=""
OSTICKET_INSTALL_SECRET=""
OSTICKET_ADMIN_PASSWORD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --terraform-root)
      TF_ROOT="$2"
      shift 2
      ;;
    --lz0-dir)
      LZ0_DIR="$2"
      shift 2
      ;;
    --lz1-dir)
      LZ1_DIR="$2"
      shift 2
      ;;
    --lz2-dir)
      LZ2_DIR="$2"
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
    --osticket-db-password)
      OSTICKET_DB_PASSWORD="$2"
      shift 2
      ;;
    --osticket-install-secret)
      OSTICKET_INSTALL_SECRET="$2"
      shift 2
      ;;
    --osticket-admin-password)
      OSTICKET_ADMIN_PASSWORD="$2"
      shift 2
      ;;
    --skip-k8s-apps)
      SKIP_K8S_APPS="true"
      shift
      ;;
    --skip-bootstrap)
      SKIP_BOOTSTRAP="true"
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

if [[ "${TF_ROOT}" != /* ]]; then
  TF_ROOT="${REPO_ROOT}/${TF_ROOT}"
fi

LZ0_PATH="${TF_ROOT}/${LZ0_DIR}"
LZ1_PATH="${TF_ROOT}/${LZ1_DIR}"
LZ2_PATH="${TF_ROOT}/${LZ2_DIR}"

require_cmd terraform

if [[ -z "${ODOO_DB_PASSWORD}" || -z "${MOODLE_DB_PASSWORD}" || -z "${OSTICKET_DB_PASSWORD}" || -z "${OSTICKET_INSTALL_SECRET}" || -z "${OSTICKET_ADMIN_PASSWORD}" ]]; then
  echo "Error: missing required secrets for lz2 apply." >&2
  exit 1
fi

for dir in "${LZ0_PATH}" "${LZ1_PATH}" "${LZ2_PATH}"; do
  if [[ ! -d "${dir}" ]]; then
    echo "Error: landing zone directory not found: ${dir}" >&2
    exit 1
  fi
done

echo "Applying Level 0 (storage/foundation): ${LZ0_PATH}"
terraform -chdir="${LZ0_PATH}" init -input=false
terraform -chdir="${LZ0_PATH}" apply -auto-approve -input=false \
  -var="aws_region=${AWS_REGION}"

echo "Applying Level 1 (network): ${LZ1_PATH}"
terraform -chdir="${LZ1_PATH}" init -input=false
terraform -chdir="${LZ1_PATH}" apply -auto-approve -input=false \
  -var="aws_region=${AWS_REGION}"

echo "Applying Level 2 (platform/apps): ${LZ2_PATH}"
terraform -chdir="${LZ2_PATH}" init -input=false
terraform -chdir="${LZ2_PATH}" apply -auto-approve -input=false \
  -var="aws_region=${AWS_REGION}" \
  -var="state_region=${AWS_REGION}" \
  -var="odoo_db_password=${ODOO_DB_PASSWORD}" \
  -var="moodle_db_password=${MOODLE_DB_PASSWORD}" \
  -var="osticket_db_password=${OSTICKET_DB_PASSWORD}" \
  -var="osticket_install_secret=${OSTICKET_INSTALL_SECRET}" \
  -var="osticket_admin_password=${OSTICKET_ADMIN_PASSWORD}"

if [[ "${SKIP_K8S_APPS}" != "true" ]]; then
  echo "Applying Kubernetes app manifests..."
  "${SCRIPT_DIR}/deploy-k8s-apps.sh" \
    --terraform-dir "${LZ2_PATH}" \
    --aws-region "${AWS_REGION}" \
    --skip-odoo-rollout-wait
fi

if [[ "${SKIP_BOOTSTRAP}" != "true" ]]; then
  if [[ "${SKIP_K8S_APPS}" == "true" ]]; then
    echo "Warning: --skip-k8s-apps was set. Bootstrap assumes Kubernetes app manifests already exist."
  fi

  echo "Running application bootstrap from existing ECR image..."
  "${SCRIPT_DIR}/deploy-odoo-image-to-eks.sh" \
    --terraform-dir "${LZ2_PATH}" \
    --aws-region "${AWS_REGION}" \
    --skip-image-push \
    --skip-deploy \
    --odoo-db-password "${ODOO_DB_PASSWORD}" \
    --moodle-db-password "${MOODLE_DB_PASSWORD}" \
    --osticket-db-password "${OSTICKET_DB_PASSWORD}" \
    --osticket-install-secret "${OSTICKET_INSTALL_SECRET}" \
    --osticket-admin-password "${OSTICKET_ADMIN_PASSWORD}"
fi

echo "Landing zones apply complete."
