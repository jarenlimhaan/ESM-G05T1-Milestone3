#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Destroy landing zone layers in reverse order: lz2 -> lz1 -> lz0.

Usage:
  ./scripts/destroy-landing-zones.sh \
    [--terraform-root terraform] \
    [--lz0-dir lz0-storage] \
    [--lz1-dir lz1-network] \
    [--lz2-dir lz2-orchestration] \
    [--aws-region ap-southeast-1] \
    [--odoo-db-password \"...\"] \
    [--moodle-db-password \"...\"] \
    [--osticket-db-password \"...\"] \
    [--osticket-install-secret \"...\"] \
    [--osticket-admin-password \"...\"] \
    [--skip-k8s-cleanup]
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
SKIP_K8S_CLEANUP="false"
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
    --skip-k8s-cleanup)
      SKIP_K8S_CLEANUP="true"
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

if [[ "${SKIP_K8S_CLEANUP}" != "true" ]]; then
  if [[ -x "${SCRIPT_DIR}/destroy-everything.sh" ]]; then
    "${SCRIPT_DIR}/destroy-everything.sh" \
      --terraform-dir "${LZ2_PATH}" \
      --skip-terraform
  fi
fi

for dir in "${LZ2_PATH}" "${LZ1_PATH}" "${LZ0_PATH}"; do
  if [[ ! -d "${dir}" ]]; then
    echo "Skipping missing landing zone directory: ${dir}"
    continue
  fi
  echo "Destroying ${dir}"
  terraform -chdir="${dir}" init -input=false
  if [[ "${dir}" == "${LZ2_PATH}" ]]; then
    terraform -chdir="${dir}" destroy -auto-approve -input=false \
      -var="aws_region=${AWS_REGION}" \
      -var="state_region=${AWS_REGION}" \
      -var="odoo_db_password=${ODOO_DB_PASSWORD}" \
      -var="moodle_db_password=${MOODLE_DB_PASSWORD}" \
      -var="osticket_db_password=${OSTICKET_DB_PASSWORD}" \
      -var="osticket_install_secret=${OSTICKET_INSTALL_SECRET}" \
      -var="osticket_admin_password=${OSTICKET_ADMIN_PASSWORD}"
  else
    terraform -chdir="${dir}" destroy -auto-approve -input=false \
      -var="aws_region=${AWS_REGION}"
  fi
done

echo "Landing zones destroy complete."
