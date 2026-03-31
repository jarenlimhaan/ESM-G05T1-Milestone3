#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Install/upgrade ArgoCD on EKS and apply local Argo Application manifest.

Usage:
  ./scripts/install-argocd.sh \
    [--terraform-dir terraform] \
    [--cluster-name <eks-cluster-name>] \
    [--aws-region ap-southeast-1] \
    [--app-file argocd/application.yaml] \
    [--skip-application]

Notes:
  - If --cluster-name/--aws-region are omitted, values are read from Terraform outputs.
  - The script refreshes kubeconfig before installing ArgoCD.
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
CLUSTER_NAME=""
AWS_REGION=""
APP_FILE="${REPO_ROOT}/argocd/application.yaml"
SKIP_APPLICATION="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --terraform-dir)
      TERRAFORM_DIR="$2"
      shift 2
      ;;
    --cluster-name)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    --aws-region)
      AWS_REGION="$2"
      shift 2
      ;;
    --app-file)
      APP_FILE="$2"
      shift 2
      ;;
    --skip-application)
      SKIP_APPLICATION="true"
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
if [[ "${APP_FILE}" != /* ]]; then
  APP_FILE="${REPO_ROOT}/${APP_FILE}"
fi

require_cmd terraform
require_cmd aws
require_cmd kubectl

if [[ -z "${CLUSTER_NAME}" ]]; then
  CLUSTER_NAME="$(terraform -chdir="${TERRAFORM_DIR}" output -raw eks_cluster_name 2>/dev/null || true)"
fi
if [[ -z "${AWS_REGION}" ]]; then
  AWS_REGION="$(terraform -chdir="${TERRAFORM_DIR}" output -raw aws_region 2>/dev/null || true)"
fi

if [[ -z "${CLUSTER_NAME}" || -z "${AWS_REGION}" ]]; then
  echo "Error: unable to resolve cluster name/region. Pass --cluster-name and --aws-region." >&2
  exit 1
fi

echo "Checking EKS cluster status for ${CLUSTER_NAME} (${AWS_REGION})..."
STATUS="$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --query 'cluster.status' --output text)"
if [[ "${STATUS}" != "ACTIVE" ]]; then
  echo "Error: cluster status is '${STATUS}' (expected ACTIVE)." >&2
  exit 1
fi

echo "Refreshing kubeconfig..."
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null

echo "Installing/upgrading ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for ArgoCD server deployment..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=600s

if [[ "${SKIP_APPLICATION}" != "true" ]]; then
  if [[ ! -f "${APP_FILE}" ]]; then
    echo "Error: application file not found: ${APP_FILE}" >&2
    exit 1
  fi
  echo "Applying ArgoCD application manifest: ${APP_FILE}"
  kubectl apply -f "${APP_FILE}"
  kubectl get applications.argoproj.io -n argocd
fi

echo "Done."
