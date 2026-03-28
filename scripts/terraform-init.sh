#!/usr/bin/env bash
set -euo pipefail

TERRAFORM_DIR="${1:-terraform}"
BACKEND_HCL="${TERRAFORM_DIR}/backend.hcl"

if [[ -f "${BACKEND_HCL}" ]]; then
  echo "Initializing Terraform with S3 backend config: ${BACKEND_HCL}"
  terraform -chdir="${TERRAFORM_DIR}" init -input=false -reconfigure -backend-config="${BACKEND_HCL}" >/dev/null
else
  echo "No backend.hcl found. Initializing Terraform in local-state mode."
  terraform -chdir="${TERRAFORM_DIR}" init -input=false -backend=false >/dev/null
fi
