#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Deploy apps if infra is up; otherwise rebuild from scratch.

Usage:
  ./scripts/deploy-or-rebuild.sh \
    [--terraform-dir terraform] \
    [--aws-region ap-southeast-1] \
    [--ecr-repo-name esm/odoo17] \
    [--target-image "<ecr-image:tag>"] \
    [--skip-image-push] \
    [--odoo-secret-id "..."] \
    [--moodle-secret-id "..."] \
    [--osticket-secret-id "..."] \
    [--odoo-db-password "..."] \
    [--moodle-db-password "..."] \
    [--osticket-db-password "..."]

Behavior:
  - If Terraform state exists and EKS cluster is ACTIVE, runs:
      ./scripts/deploy-k8s-apps.sh ...
  - Otherwise runs:
      ./scripts/rebuild-from-scratch.sh ...
  - If --skip-image-push is set and --target-image is omitted, the script
    resolves the latest tagged image from ECR repo (default: esm/odoo17).
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
AWS_REGION=""
TARGET_IMAGE=""
SKIP_IMAGE_PUSH="false"
ECR_REPO_NAME="esm/odoo17"

SHARED_ARGS=()
DEPLOY_ARGS=()
REBUILD_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --terraform-dir)
      TERRAFORM_DIR="$2"
      shift 2
      ;;
    --aws-region)
      AWS_REGION="$2"
      SHARED_ARGS+=("$1" "$2")
      DEPLOY_ARGS+=("$1" "$2")
      REBUILD_ARGS+=("$1" "$2")
      shift 2
      ;;
    --ecr-repo-name)
      ECR_REPO_NAME="$2"
      shift 2
      ;;
    --target-image)
      TARGET_IMAGE="$2"
      REBUILD_ARGS+=("$1" "$2")
      shift 2
      ;;
    --skip-image-push)
      SKIP_IMAGE_PUSH="true"
      REBUILD_ARGS+=("$1")
      shift
      ;;
    --odoo-secret-id|--moodle-secret-id|--osticket-secret-id|--odoo-db-password|--moodle-db-password|--osticket-db-password)
      SHARED_ARGS+=("$1" "$2")
      DEPLOY_ARGS+=("$1" "$2")
      REBUILD_ARGS+=("$1" "$2")
      shift 2
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

cluster_name=""
if terraform -chdir="${TERRAFORM_DIR}" output -raw eks_cluster_name >/dev/null 2>&1; then
  cluster_name="$(terraform -chdir="${TERRAFORM_DIR}" output -raw eks_cluster_name)"
fi

if [[ -z "${AWS_REGION}" ]]; then
  if terraform -chdir="${TERRAFORM_DIR}" output -raw aws_region >/dev/null 2>&1; then
    AWS_REGION="$(terraform -chdir="${TERRAFORM_DIR}" output -raw aws_region)"
    DEPLOY_ARGS+=(--aws-region "${AWS_REGION}")
  fi
fi

if [[ "${SKIP_IMAGE_PUSH}" == "true" && -z "${TARGET_IMAGE}" ]]; then
  if [[ -z "${AWS_REGION}" ]]; then
    AWS_REGION="$(aws configure get region 2>/dev/null || true)"
  fi
  if [[ -z "${AWS_REGION}" ]]; then
    echo "Error: AWS region is required to resolve latest ECR image. Pass --aws-region." >&2
    exit 1
  fi

  account_id="$(aws sts get-caller-identity --query Account --output text)"
  latest_tag="$(
    aws ecr describe-images \
      --region "${AWS_REGION}" \
      --repository-name "${ECR_REPO_NAME}" \
      --query "reverse(sort_by(imageDetails[?imageTags!=null], &imagePushedAt))[0].imageTags[0]" \
      --output text 2>/dev/null || true
  )"

  if [[ -z "${latest_tag}" || "${latest_tag}" == "None" ]]; then
    echo "Error: unable to resolve latest tagged image from ECR repo '${ECR_REPO_NAME}'." >&2
    echo "Pass --target-image explicitly, or ensure the ECR repo has tagged images." >&2
    exit 1
  fi

  TARGET_IMAGE="${account_id}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:${latest_tag}"
  REBUILD_ARGS+=(--target-image "${TARGET_IMAGE}")
  echo "Resolved latest ECR image: ${TARGET_IMAGE}"
fi

infra_up="false"
if [[ -n "${cluster_name}" && -n "${AWS_REGION}" ]]; then
  cluster_status="$(aws eks describe-cluster --name "${cluster_name}" --region "${AWS_REGION}" --query 'cluster.status' --output text 2>/dev/null || true)"
  if [[ "${cluster_status}" == "ACTIVE" ]]; then
    infra_up="true"
  fi
fi

if [[ "${infra_up}" == "true" ]]; then
  echo "Infra is up (EKS cluster ${cluster_name} is ACTIVE). Running deploy-k8s-apps.sh..."
  "${SCRIPT_DIR}/deploy-k8s-apps.sh" --terraform-dir "${TERRAFORM_DIR}" "${DEPLOY_ARGS[@]}"
else
  echo "Infra is not up. Running rebuild-from-scratch.sh..."
  "${SCRIPT_DIR}/rebuild-from-scratch.sh" "${REBUILD_ARGS[@]}"
fi
