#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/destroy-everything.sh \
    [--terraform-dir terraform] \
    [--k8s-dir k8s] \
    [--namespace esm] \
    [--skip-k8s] \
    [--skip-terraform] \
    [--skip-snapshot-cleanup]

Options:
  --terraform-dir         Terraform directory (default: terraform).
  --k8s-dir               Kubernetes manifests directory (default: k8s).
  --namespace             Kubernetes namespace (default: esm).
  --skip-k8s              Skip Kubernetes cleanup.
  --skip-terraform        Skip Terraform destroy.
  --skip-snapshot-cleanup Skip pre-delete of known final snapshot names.
  -h, --help              Show this help.
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
NAMESPACE="esm"
SKIP_K8S="false"
SKIP_TERRAFORM="false"
SKIP_SNAPSHOT_CLEANUP="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --terraform-dir)
      TERRAFORM_DIR="$2"
      shift 2
      ;;
    --k8s-dir)
      K8S_DIR="$2"
      shift 2
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --skip-k8s)
      SKIP_K8S="true"
      shift
      ;;
    --skip-terraform)
      SKIP_TERRAFORM="true"
      shift
      ;;
    --skip-snapshot-cleanup)
      SKIP_SNAPSHOT_CLEANUP="true"
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
if [[ "${K8S_DIR}" != /* ]]; then
  K8S_DIR="${REPO_ROOT}/${K8S_DIR}"
fi

require_cmd terraform
require_cmd aws

AWS_REGION="$(terraform -chdir="${TERRAFORM_DIR}" output -raw aws_region 2>/dev/null || true)"
CLUSTER_NAME="$(terraform -chdir="${TERRAFORM_DIR}" output -raw eks_cluster_name 2>/dev/null || true)"

if [[ -z "${AWS_REGION}" ]]; then
  AWS_REGION="ap-southeast-1"
fi

if [[ "${SKIP_K8S}" != "true" ]]; then
  require_cmd kubectl
  echo "Cleaning Kubernetes resources first..."

  if [[ -n "${CLUSTER_NAME}" ]]; then
    aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1 || true
  fi

  # Explicitly remove LB services to avoid orphan NLB dependencies at destroy time.
  kubectl delete svc odoo-public moodle-vpn odoo-vpn moodle-public -n "${NAMESPACE}" --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete -k "${K8S_DIR}" --ignore-not-found=true >/dev/null 2>&1 || true
fi

if [[ "${SKIP_TERRAFORM}" == "true" ]]; then
  echo "Skipping Terraform destroy (--skip-terraform)."
  exit 0
fi

if [[ "${SKIP_SNAPSHOT_CLEANUP}" != "true" ]]; then
  echo "Deleting known final snapshots if they exist (to prevent DBSnapshotAlreadyExists)..."
  for snapshot in \
    "esm-enterprise-prod-odoo-final-snapshot" \
    "esm-enterprise-prod-moodle-final-snapshot"; do
    if aws rds describe-db-snapshots \
      --region "${AWS_REGION}" \
      --db-snapshot-identifier "${snapshot}" \
      >/dev/null 2>&1; then
      aws rds delete-db-snapshot \
        --region "${AWS_REGION}" \
        --db-snapshot-identifier "${snapshot}" \
        >/dev/null
      echo "Requested delete for snapshot: ${snapshot}"
    fi
  done
fi

echo "Running Terraform destroy..."
terraform -chdir="${TERRAFORM_DIR}" destroy -auto-approve

echo "Done. Stack teardown complete."
