#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Rebuild full project stack from scratch.

Usage:
  ./scripts/rebuild-from-scratch.sh \
    [--skip-destroy] \
    [--skip-image-push] \
    [--target-image "<registry/repo:tag>"] \
    [--odoo-db-password "..."] \
    [--moodle-db-password "..."] \
    [--osticket-db-password "..."] \
    [--odoo-secret-id "..."] \
    [--moodle-secret-id "..."] \
    [--osticket-secret-id "..."]

Notes:
  - By default this script destroys existing stack first.
  - Then it runs deploy-odoo-image-to-eks.sh with --provision-infra.
  - If Docker is unavailable, this script auto-adds --skip-image-push.
  - For full rebuild (without --skip-destroy) and --skip-image-push,
    you must provide --target-image.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SKIP_DESTROY="false"
HAS_SKIP_IMAGE_PUSH_ARG="false"
HAS_TARGET_IMAGE_ARG="false"
ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-destroy)
      SKIP_DESTROY="true"
      shift
      ;;
    --skip-image-push)
      HAS_SKIP_IMAGE_PUSH_ARG="true"
      ARGS+=("$1")
      shift
      ;;
    --target-image)
      HAS_TARGET_IMAGE_ARG="true"
      ARGS+=("$1" "$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ "${SKIP_DESTROY}" != "true" ]]; then
  "${SCRIPT_DIR}/destroy-everything.sh"
fi

if ! command -v docker >/dev/null 2>&1; then
  if [[ "${HAS_SKIP_IMAGE_PUSH_ARG}" != "true" ]]; then
    ARGS+=(--skip-image-push)
  fi
  if [[ "${SKIP_DESTROY}" != "true" && "${HAS_TARGET_IMAGE_ARG}" != "true" ]]; then
    echo "Error: Docker is unavailable. For full rebuild, pass --target-image with an existing ECR image." >&2
    exit 1
  fi
fi

"${SCRIPT_DIR}/deploy-odoo-image-to-eks.sh" --provision-infra "${ARGS[@]}"

echo "Rebuild complete."
