#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Sync Kubernetes DB secrets from AWS Secrets Manager.

Usage:
  ./scripts/sync-k8s-secrets-from-aws.sh \
    --region ap-southeast-1 \
    [--odoo-secret-id esm/prod/odoo-db-password] \
    [--moodle-secret-id esm/prod/moodle-db-password] \
    [--osticket-secret-id esm/prod/osticket-db-password] \
    [--moodle-admin-password "<password>"] \
    [--osticket-install-secret "<secret>"] \
    [--osticket-admin-password "<password>"]

Notes:
  - Secret value is read from SecretString as plain text password.
  - If --osticket-secret-id is omitted, Moodle password is reused for osTicket.
  - Moodle admin password default is read from .env (MOODLE_ADMIN_PASSWORD).
  - osTicket install/admin secret defaults are read from .env (INSTALL_SECRET, ADMIN_PASSWORD).
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

read_dotenv_value() {
  local key="$1"
  local env_file="${REPO_ROOT}/.env"
  local line=""
  if [[ ! -f "${env_file}" ]]; then
    return 0
  fi
  line="$(grep -E "^${key}=" "${env_file}" | tail -n 1 || true)"
  if [[ -n "${line}" ]]; then
    printf '%s' "${line#*=}" | tr -d '\r'
  fi
}

REGION=""
ODOO_SECRET_ID="esm/prod/odoo-db-password"
MOODLE_SECRET_ID="esm/prod/moodle-db-password"
OSTICKET_SECRET_ID="esm/prod/osticket-db-password"
MOODLE_ADMIN_PASSWORD="$(read_dotenv_value MOODLE_ADMIN_PASSWORD)"
if [[ -z "${MOODLE_ADMIN_PASSWORD}" ]]; then
  MOODLE_ADMIN_PASSWORD="Admin~1234"
fi
OSTICKET_INSTALL_SECRET="$(read_dotenv_value INSTALL_SECRET)"
if [[ -z "${OSTICKET_INSTALL_SECRET}" ]]; then
  OSTICKET_INSTALL_SECRET="put-a-long-random-string-here-please-change-me"
fi
OSTICKET_ADMIN_PASSWORD="$(read_dotenv_value ADMIN_PASSWORD)"
if [[ -z "${OSTICKET_ADMIN_PASSWORD}" ]]; then
  OSTICKET_ADMIN_PASSWORD="ChangeThisAdminPassword123!"
fi

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
    --moodle-admin-password)
      MOODLE_ADMIN_PASSWORD="$2"
      shift 2
      ;;
    --osticket-install-secret)
      OSTICKET_INSTALL_SECRET="$2"
      shift 2
      ;;
    --osticket-admin-password)
      OSTICKET_ADMIN_PASSWORD="$2"
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

if [[ -z "${REGION}" ]]; then
  echo "Error: --region is required." >&2
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
  --from-literal=admin_password="${MOODLE_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic osticket-db -n osticket-private \
  --from-literal=password="${OSTICKET_DB_PASSWORD}" \
  --from-literal=install_secret="${OSTICKET_INSTALL_SECRET}" \
  --from-literal=admin_password="${OSTICKET_ADMIN_PASSWORD}" \
  --from-literal=db_username="moodle_admin" \
  --from-literal=db_password="${MOODLE_DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Done. Restarting app deployments to pick up new secret values..."
kubectl get deployment/odoo-private  -n odoo-private   &>/dev/null && kubectl rollout restart deployment/odoo-private  -n odoo-private   || echo "  [skip] odoo-private not deployed yet"
kubectl get deployment/odoo-public   -n odoo-public    &>/dev/null && kubectl rollout restart deployment/odoo-public   -n odoo-public    || echo "  [skip] odoo-public not deployed yet"
kubectl get deployment/moodle        -n moodle-private &>/dev/null && kubectl rollout restart deployment/moodle        -n moodle-private || echo "  [skip] moodle not deployed yet"
kubectl get deployment/osticket      -n osticket-private &>/dev/null && kubectl rollout restart deployment/osticket    -n osticket-private || echo "  [skip] osticket not deployed yet"

echo "Secret sync complete."
