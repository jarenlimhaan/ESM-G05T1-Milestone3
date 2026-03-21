#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Rebuild full project stack from scratch.

Usage:
  ./scripts/rebuild-from-scratch.sh \
    [--skip-destroy] \
    [--odoo-db-password "..."] \
    [--moodle-db-password "..."] \
    [--osticket-db-password "..."] \
    [--odoo-secret-id "..."] \
    [--moodle-secret-id "..."] \
    [--osticket-secret-id "..."]

Notes:
  - By default this script destroys existing stack first.
  - Then it runs deploy script with --provision-infra.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SKIP_DESTROY="false"
ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-destroy)
      SKIP_DESTROY="true"
      shift
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

"${SCRIPT_DIR}/deploy-k8s-apps.sh" --provision-infra "${ARGS[@]}"

echo "Rebuild complete."
