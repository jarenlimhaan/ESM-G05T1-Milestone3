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
    [--allow-destroy] \
    [--target-image "<ecr-image:tag>"] \
    [--skip-image-push] \
    [--odoo-secret-id "..."] \
    [--moodle-secret-id "..."] \
    [--osticket-secret-id "..."] \
    [--odoo-db-password "..."] \
    [--moodle-db-password "..."] \
    [--osticket-db-password "..."]

Behavior:
  - If Terraform state exists and EKS cluster is ACTIVE, runs bootstrap flow:
      ./scripts/deploy-odoo-image-to-eks.sh --skip-image-push ...
  - Otherwise runs rebuild flow:
      ./scripts/rebuild-from-scratch.sh ...
    By default it uses --skip-destroy for safety.
    Pass --allow-destroy to permit full teardown before rebuild.
  - If EKS is in a transitional state (CREATING/UPDATING/DELETING),
    script exits without destroy/apply to avoid lock/state corruption.
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
ALLOW_DESTROY="false"

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
    --allow-destroy)
      ALLOW_DESTROY="true"
      shift
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
cluster_status=""
infra_reason="terraform output eks_cluster_name unavailable"
if terraform -chdir="${TERRAFORM_DIR}" output -raw eks_cluster_name >/dev/null 2>&1; then
  cluster_name="$(terraform -chdir="${TERRAFORM_DIR}" output -raw eks_cluster_name)"
  if [[ -n "${cluster_name}" ]]; then
    infra_reason="EKS cluster name found in Terraform output: ${cluster_name}"
  else
    infra_reason="terraform output eks_cluster_name is empty"
  fi
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
  if [[ "${cluster_status}" == "CREATING" || "${cluster_status}" == "UPDATING" || "${cluster_status}" == "DELETING" ]]; then
    echo "EKS cluster '${cluster_name}' is currently '${cluster_status}'."
    echo "Aborting to avoid lock contention. Wait until status is ACTIVE (or fully deleted), then rerun."
    exit 1
  fi
  if [[ "${cluster_status}" == "ACTIVE" ]]; then
    infra_up="true"
    infra_reason="EKS cluster '${cluster_name}' is ACTIVE"
  elif [[ -n "${cluster_status}" ]]; then
    infra_reason="EKS cluster '${cluster_name}' status is '${cluster_status}'"
  else
    infra_reason="EKS cluster '${cluster_name}' not found or not readable in region ${AWS_REGION}"
  fi
elif [[ -z "${AWS_REGION}" ]]; then
  infra_reason="${infra_reason}; AWS region is empty"
fi

if [[ "${infra_up}" == "true" ]]; then
  echo "Infra is up (EKS cluster ${cluster_name} is ACTIVE). Running bootstrap deploy without image push..."
  BOOTSTRAP_ARGS=(
    --terraform-dir "${TERRAFORM_DIR}"
    --skip-image-push
    "${SHARED_ARGS[@]}"
  )
  if [[ -n "${AWS_REGION}" ]]; then
    BOOTSTRAP_ARGS+=(--aws-region "${AWS_REGION}")
  fi
  if [[ -n "${TARGET_IMAGE}" ]]; then
    BOOTSTRAP_ARGS+=(--target-image "${TARGET_IMAGE}")
  fi
  "${SCRIPT_DIR}/deploy-odoo-image-to-eks.sh" "${BOOTSTRAP_ARGS[@]}"
else
  echo "Infra is not up. Reason: ${infra_reason}"
  echo "Running rebuild-from-scratch.sh..."
  if [[ "${ALLOW_DESTROY}" != "true" ]]; then
    echo "Safety mode: adding --skip-destroy. Use --allow-destroy to permit teardown."
    REBUILD_ARGS+=(--skip-destroy)
  fi
  if [[ "${SKIP_IMAGE_PUSH}" != "true" ]]; then
    REBUILD_ARGS+=(--skip-image-push)
  fi
  "${SCRIPT_DIR}/rebuild-from-scratch.sh" "${REBUILD_ARGS[@]}"
fi
