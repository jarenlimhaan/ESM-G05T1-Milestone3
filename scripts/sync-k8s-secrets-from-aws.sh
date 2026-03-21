#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Sync Kubernetes DB secrets from AWS Secrets Manager.

Usage:
  ./scripts/sync-k8s-secrets-from-aws.sh \
    --region ap-southeast-1 \
    --odoo-secret-id esm/prod/odoo-db-password \
    --moodle-secret-id esm/prod/moodle-db-password \
    --osticket-secret-id esm/prod/osticket-db-password

Notes:
  - Secret value is read from SecretString as plain text password.
  - If --osticket-secret-id is omitted, Moodle password is reused for osTicket.
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' not found." >&2
    exit 1
  fi
}

REGION=""
ODOO_SECRET_ID=""
MOODLE_SECRET_ID=""
OSTICKET_SECRET_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      REGION="$2"
      shift 2
      ;;
    --odoo-secret-id)
      ODOO_SECRET_ID="$2"
      shift 2
      ;;
    --moodle-secret-id)
      MOODLE_SECRET_ID="$2"
      shift 2
      ;;
    --osticket-secret-id)
      OSTICKET_SECRET_ID="$2"
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

if [[ -z "${REGION}" || -z "${ODOO_SECRET_ID}" || -z "${MOODLE_SECRET_ID}" ]]; then
  echo "Error: --region, --odoo-secret-id, and --moodle-secret-id are required." >&2
  usage
  exit 1
fi

if [[ -z "${OSTICKET_SECRET_ID}" ]]; then
  OSTICKET_SECRET_ID="${MOODLE_SECRET_ID}"
fi

require_cmd aws
require_cmd kubectl

get_secret_value() {
  local secret_id="$1"
  aws secretsmanager get-secret-value \
    --region "${REGION}" \
    --secret-id "${secret_id}" \
    --query SecretString \
    --output text
}

echo "Fetching secrets from AWS Secrets Manager..."
ODOO_DB_PASSWORD="$(get_secret_value "${ODOO_SECRET_ID}")"
MOODLE_DB_PASSWORD="$(get_secret_value "${MOODLE_SECRET_ID}")"
OSTICKET_DB_PASSWORD="$(get_secret_value "${OSTICKET_SECRET_ID}")"

echo "Applying Kubernetes secrets..."
kubectl create secret generic odoo-db -n odoo-private \
  --from-literal=password="${ODOO_DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic odoo-db -n odoo-public \
  --from-literal=password="${ODOO_DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic moodle-db -n moodle-private \
  --from-literal=password="${MOODLE_DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic osticket-db -n osticket-private \
  --from-literal=password="${OSTICKET_DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Done. Restarting app deployments to pick up new secret values..."
kubectl rollout restart deployment/odoo-private -n odoo-private
kubectl rollout restart deployment/odoo-public -n odoo-public
kubectl rollout restart deployment/moodle -n moodle-private
kubectl rollout restart deployment/osticket -n osticket-private

echo "Secret sync complete."
