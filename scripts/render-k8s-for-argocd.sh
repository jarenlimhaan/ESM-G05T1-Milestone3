#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Render ArgoCD-ready manifests to k8s-rendered/ (no kubectl apply).

Usage:
  ./scripts/render-k8s-for-argocd.sh \
    [--output-dir k8s-rendered] \
    [--terraform-dir terraform] \
    [--aws-region ap-southeast-1] \
    [any deploy-k8s-apps.sh args...]
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

OUTPUT_DIR="${REPO_ROOT}/k8s-rendered"
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --terraform-dir|--aws-region|--odoo-db-user|--odoo-image|--odoo-db-password|--moodle-db-user|--moodle-db-password|--moodle-db-name|--moodle-image|--moodle-admin-user|--moodle-admin-password|--moodle-admin-email|--moodle-url|--osticket-image|--osticket-db-host|--osticket-db-user|--osticket-db-password|--osticket-db-name|--osticket-install-secret|--osticket-install-name|--osticket-install-url|--osticket-install-email|--osticket-admin-firstname|--osticket-admin-lastname|--osticket-admin-email|--osticket-admin-username|--osticket-admin-password|--osticket-cron-interval|--odoo-secret-id|--moodle-secret-id|--osticket-secret-id|--include-k8s-secrets-manifest|--provision-infra)
      EXTRA_ARGS+=("$1")
      if [[ "$1" != "--include-k8s-secrets-manifest" && "$1" != "--provision-infra" ]]; then
        EXTRA_ARGS+=("$2")
        shift
      fi
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

if [[ "${OUTPUT_DIR}" != /* ]]; then
  OUTPUT_DIR="${REPO_ROOT}/${OUTPUT_DIR}"
fi

"${SCRIPT_DIR}/deploy-k8s-apps.sh" \
  --render-only \
  --render-output-dir "${OUTPUT_DIR}" \
  "${EXTRA_ARGS[@]}"

echo "Done. ArgoCD manifests rendered at: ${OUTPUT_DIR}"
