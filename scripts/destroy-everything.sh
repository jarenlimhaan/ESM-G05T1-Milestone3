#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/destroy-everything.sh \
    [--terraform-dir terraform/lz2-orchestration] \
    [--k8s-dir k8s] \
    [--namespace odoo-public] \
    [--skip-k8s] \
    [--skip-terraform] \
    [--skip-snapshot-cleanup] \
    [--skip-backup-cleanup]

Options:
  --terraform-dir         Terraform directory (default: terraform/lz2-orchestration).
  --k8s-dir               Kubernetes manifests directory (default: k8s).
  --namespace             Kubernetes namespace (legacy option, default: odoo-public).
  --skip-k8s              Skip Kubernetes cleanup.
  --skip-terraform        Skip Terraform destroy.
  --skip-snapshot-cleanup Skip pre-delete of known final snapshot names.
  --skip-backup-cleanup   Skip deleting AWS Backup recovery points.
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

TERRAFORM_DIR="${REPO_ROOT}/terraform/lz2-orchestration"
K8S_DIR="${REPO_ROOT}/k8s"
NAMESPACE="odoo-public"
SKIP_K8S="false"
SKIP_TERRAFORM="false"
SKIP_SNAPSHOT_CLEANUP="false"
SKIP_BACKUP_CLEANUP="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --terraform-dir)
      TERRAFORM_DIR="$2"
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
    --skip-backup-cleanup)
      SKIP_BACKUP_CLEANUP="true"
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

require_cmd terraform
require_cmd aws

# Fresh CI runners don't have .terraform modules initialized yet.
echo "Initializing Terraform in ${TERRAFORM_DIR}..."
terraform -chdir="${TERRAFORM_DIR}" init -input=false >/dev/null

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

  # Remove Ingresses first so the ALB controller can deprovision the load balancers
  # before Terraform destroys the VPC/SGs they depend on.
  kubectl delete ingress odoo-private -n odoo-private --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete ingress odoo-public -n odoo-public --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete ingress moodle -n moodle-private --ignore-not-found >/dev/null 2>&1 || true
  kubectl delete ingress osticket -n osticket-private --ignore-not-found >/dev/null 2>&1 || true
  echo "Waiting 15s for ALB controller to deprovision load balancers..."
  sleep 15
  # Delete workload namespaces (removes all Helm-managed resources within them)
  kubectl delete namespace odoo-private odoo-public moodle-private osticket-private --ignore-not-found >/dev/null 2>&1 || true
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

if [[ "${SKIP_BACKUP_CLEANUP}" != "true" ]]; then
  BACKUP_VAULT_ARN="$(terraform -chdir="${TERRAFORM_DIR}" output -raw backup_vault_arn 2>/dev/null || true)"
  if [[ -n "${BACKUP_VAULT_ARN}" ]]; then
    BACKUP_VAULT_NAME="${BACKUP_VAULT_ARN##*:}"
    echo "Deleting recovery points in backup vault ${BACKUP_VAULT_NAME}..."
    while IFS= read -r RP_ARN; do
      if [[ -n "${RP_ARN}" ]]; then
        aws backup delete-recovery-point \
          --region "${AWS_REGION}" \
          --backup-vault-name "${BACKUP_VAULT_NAME}" \
          --recovery-point-arn "${RP_ARN}" \
          >/dev/null || true
        echo "Requested delete for recovery point: ${RP_ARN}"
      fi
    done < <(
      aws backup list-recovery-points-by-backup-vault \
        --region "${AWS_REGION}" \
        --backup-vault-name "${BACKUP_VAULT_NAME}" \
        --query 'RecoveryPoints[].RecoveryPointArn' \
        --output text 2>/dev/null | tr '\t' '\n'
    )
  fi
fi

echo "Running Terraform destroy..."
terraform -chdir="${TERRAFORM_DIR}" destroy -auto-approve

echo "Done. Stack teardown complete."
