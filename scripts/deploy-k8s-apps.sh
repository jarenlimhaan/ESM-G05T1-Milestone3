#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/deploy-k8s-apps.sh \
    [--odoo-db-password "<password>"] \
    [--moodle-db-password "<password>"] \
    [--osticket-db-password "<password>"] \
    [--odoo-secret-id "<aws-secretsmanager-id>"] \
    [--moodle-secret-id "<aws-secretsmanager-id>"] \
    [--osticket-secret-id "<aws-secretsmanager-id>"] \
    [--terraform-dir terraform] \
    [--aws-region ap-southeast-1] \
    [--odoo-db-user odoo_admin] \
    [--odoo-image "<image-ref>"] \
    [--moodle-db-user moodle_admin] \
    [--moodle-db-name moodledb] \
    [--moodle-image "<image-ref>"] \
    [--moodle-admin-user admin] \
    [--moodle-admin-password "Admin~1234"] \
    [--moodle-admin-email "admin@esmos.meals.sg"] \
    [--moodle-url "http://moodle.internal.esm.local"] \
    [--osticket-image "<image-ref>"] \
    [--osticket-db-host "<host>"] \
    [--osticket-db-user moodle_admin] \
    [--osticket-db-name osticketdb] \
    [--osticket-install-secret "<secret>"] \
    [--osticket-install-name "My Helpdesk"] \
    [--osticket-install-url "http://osticket.internal.esm.local"] \
    [--osticket-install-email "helpdesk@example.com"] \
    [--osticket-admin-firstname "Admin"] \
    [--osticket-admin-lastname "User"] \
    [--osticket-admin-email "admin@example.com"] \
    [--osticket-admin-username "ostadmin"] \
    [--osticket-admin-password "ChangeThisAdminPassword123!"] \
    [--osticket-cron-interval 5] \
    [--skip-odoo-rollout-wait] \
    [--include-k8s-secrets-manifest] \
    [--render-only] \
    [--render-output-dir k8s-rendered] \
    [--keep-rendered-manifests] \
    [--provision-infra]

Options:
  --odoo-db-password     Odoo password for secret/odoo-db.
  --moodle-db-password   Moodle password for secret/moodle-db.
  --osticket-db-password Optional. Password for secret/osticket-db.
                         Defaults to --moodle-db-password value.
  --odoo-secret-id       AWS Secrets Manager secret id for Odoo DB password.
  --moodle-secret-id     AWS Secrets Manager secret id for Moodle DB password.
  --osticket-secret-id   AWS Secrets Manager secret id for osTicket DB password.
                         If omitted, Moodle secret/password is reused.
  --terraform-dir        Terraform directory (default: terraform).
  --aws-region           AWS region. If omitted, read from Terraform output.
  --odoo-db-user         Odoo DB user (default: odoo_admin).
  --odoo-image           Odoo container image (default: odoo:16.0).
  --moodle-db-user       Moodle DB user (default: moodle_admin).
  --moodle-db-name       Moodle DB name (default: moodledb).
  --moodle-image         Moodle container image (default: ellakcy/moodle:mysql_maria_apache_latest).
  --moodle-admin-user    Moodle admin username (default: admin).
  --moodle-admin-password
                         Moodle admin password (default: Admin~1234).
  --moodle-admin-email   Moodle admin email (default: admin@esmos.meals.sg).
  --moodle-url           Moodle URL (default: http://moodle.internal.esm.local).
  --osticket-image       osTicket container image (default: latest image from ECR repo esm/osticket, resolved at runtime).
  --osticket-db-host     osTicket DB host. Defaults to Moodle DB host output.
  --osticket-db-user     osTicket DB user (default: moodle_admin).
  --osticket-db-name     osTicket DB name (default: osticketdb).
  --osticket-install-secret
                         osTicket install secret (default: INSTALL_SECRET in .env, then built-in value).
  --osticket-install-name
                         osTicket helpdesk name (default: INSTALL_NAME in .env, then "My Helpdesk").
  --osticket-install-url
                         osTicket install URL (default: INSTALL_URL in .env, then http://osticket.internal.esm.local).
  --osticket-install-email
                         osTicket install email (default: INSTALL_EMAIL in .env, then helpdesk@example.com).
  --osticket-admin-firstname
                         osTicket admin first name (default: ADMIN_FIRSTNAME in .env, then Admin).
  --osticket-admin-lastname
                         osTicket admin last name (default: ADMIN_LASTNAME in .env, then User).
  --osticket-admin-email
                         osTicket admin email (default: ADMIN_EMAIL in .env, then admin@example.com).
  --osticket-admin-username
                         osTicket admin username (default: ADMIN_USERNAME in .env, then ostadmin).
  --osticket-admin-password
                         osTicket admin password (default: ADMIN_PASSWORD in .env, then ChangeThisAdminPassword123!).
  --osticket-cron-interval
                         osTicket cron interval minutes (default: CRON_INTERVAL in .env, then 5).
  --skip-odoo-rollout-wait
                         Skip waiting for odoo-private/odoo-public rollout status.
                         Useful when Odoo DB bootstrap is handled in a later step.
  --include-k8s-secrets-manifest
                         Include k8s/secrets.yaml in rendered apply.
                         Default is to skip it because secrets are Terraform-managed.
  --render-only          Render manifests only. Do not kubectl apply/restart/wait.
  --render-output-dir    Directory to write rendered manifests to.
  --keep-rendered-manifests
                         Keep rendered temporary manifests for inspection.
  --provision-infra      Run terraform init + apply before kubectl apply.
  -h, --help             Show this help.
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' not found." >&2
    exit 1
  fi
}

resolve_latest_ecr_image() {
  local account_id="$1"
  local region="$2"
  local repo_name="${3:-esm/odoo17}"
  local latest_tag
  latest_tag="$(
    aws ecr describe-images \
      --region "${region}" \
      --repository-name "${repo_name}" \
      --query "reverse(sort_by(imageDetails[?imageTags!=null], &imagePushedAt))[0].imageTags[0]" \
      --output text 2>/dev/null || true
  )"
  if [[ -z "${latest_tag}" || "${latest_tag}" == "None" ]]; then
    return 1
  fi
  printf '%s.dkr.ecr.%s.amazonaws.com/%s:%s' "${account_id}" "${region}" "${repo_name}" "${latest_tag}"
}

tf_output_raw() {
  local key="$1"
  local value
  local cleaned
  local err
  err="$(mktemp)"
  if ! value="$(terraform -chdir="${TERRAFORM_DIR}" output -raw "${key}" 2>"${err}")"; then
    cat "${err}" >&2 || true
    rm -f "${err}"
    echo "Error: failed reading terraform output '${key}'." >&2
    exit 1
  fi
  if grep -q "No outputs found" "${err}"; then
    rm -f "${err}"
    echo "Error: terraform state has no outputs. Run infrastructure apply first." >&2
    exit 1
  fi
  rm -f "${err}"
  cleaned="$(printf '%s' "${value}" | sed -E 's/\x1b\[[0-9;]*[mK]//g')"
  if [[ -z "${cleaned}" || "${cleaned}" == *"No outputs found"* || "${cleaned}" == *"Warning:"* ]]; then
    echo "Error: terraform output '${key}' is not available. Run infrastructure apply first." >&2
    exit 1
  fi
  printf '%s' "${cleaned}"
}

run_mysql_sql() {
  local sql="$1"
  local pod="mysql-client-$(date +%s%N | tail -c 8)"
  kubectl run "${pod}" \
    --image=mysql:8.0 \
    --restart=Never \
    --rm -i \
    --env="MYSQL_PWD=${MOODLE_DB_PASSWORD}" \
    --command -- sh -lc \
    "mysql -h '${MOODLE_DB_HOST}' -u '${MOODLE_DB_USER}' -D mysql -N -s -e \"${sql}\""
}

ensure_moodle_db_is_complete() {
  local version_raw version
  # Some Moodle images use mdl_config, others may use config.
  version_raw="$(run_mysql_sql "USE ${MOODLE_DB_NAME}; SELECT value FROM mdl_config WHERE name='version' LIMIT 1;" 2>/dev/null || true)"
  if [[ -z "${version_raw}" ]]; then
    version_raw="$(run_mysql_sql "USE ${MOODLE_DB_NAME}; SELECT value FROM config WHERE name='version' LIMIT 1;" 2>/dev/null || true)"
  fi
  version="$(printf '%s\n' "${version_raw}" | tr -d '\r' | awk '/^[0-9]+$/ {print; exit}')"
  if [[ -n "${version}" ]]; then
    echo "Moodle DB check OK (version=${version})."
    return 0
  fi

  echo "Moodle DB appears incomplete (missing mdl_config.version). Repairing..."
  run_mysql_sql "DROP DATABASE IF EXISTS ${MOODLE_DB_NAME}; CREATE DATABASE ${MOODLE_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; GRANT ALL PRIVILEGES ON ${MOODLE_DB_NAME}.* TO '${MOODLE_DB_USER}'@'%'; FLUSH PRIVILEGES;" >/dev/null

  kubectl rollout restart deployment/moodle -n moodle-private
  kubectl rollout status deployment/moodle -n moodle-private --timeout=420s

  # Give Moodle install bootstrap some time to populate mdl_config.version.
  for _ in $(seq 1 20); do
    version_raw="$(run_mysql_sql "USE ${MOODLE_DB_NAME}; SELECT value FROM mdl_config WHERE name='version' LIMIT 1;" 2>/dev/null || true)"
    if [[ -z "${version_raw}" ]]; then
      version_raw="$(run_mysql_sql "USE ${MOODLE_DB_NAME}; SELECT value FROM config WHERE name='version' LIMIT 1;" 2>/dev/null || true)"
    fi
    version="$(printf '%s\n' "${version_raw}" | tr -d '\r' | awk '/^[0-9]+$/ {print; exit}')"
    if [[ -n "${version}" ]]; then
      break
    fi
    sleep 10
  done

  if [[ -z "${version}" ]]; then
    # Fallback: if container logs show Moodle install completed, do not hard-fail.
    if kubectl logs -n moodle-private deployment/moodle --tail=400 2>/dev/null | grep -q "Installation completed successfully"; then
      echo "Warning: Moodle version check was inconclusive, but installation logs indicate success. Continuing."
      return 0
    fi
    echo "Error: Moodle DB repair did not complete (version still missing)." >&2
    return 1
  fi

  echo "Moodle DB repaired successfully (version=${version})."
}

repair_live_moodle_placeholder_env_if_needed() {
  if ! kubectl get deployment/moodle -n moodle-private >/dev/null 2>&1; then
    return 0
  fi

  local moodle_env_dump
  moodle_env_dump="$(
    kubectl get deployment/moodle -n moodle-private \
      -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' \
      2>/dev/null || true
  )"

  if [[ "${moodle_env_dump}" != *"__MOODLE_"* ]]; then
    return 0
  fi

  echo "Detected unresolved __MOODLE_*__ placeholders in live deployment; repairing Moodle env values..."
  kubectl -n moodle-private set env deployment/moodle \
    MOODLE_DB_TYPE=mariadb \
    MOODLE_DB_HOST="${MOODLE_DB_HOST}" \
    MOODLE_DB_PORT=3306 \
    MOODLE_DB_USER="${MOODLE_DB_USER}" \
    MOODLE_DB_NAME="${MOODLE_DB_NAME}" \
    MOODLE_ADMIN="${MOODLE_ADMIN_USER}" \
    MOODLE_ADMIN_PASSWORD="${MOODLE_ADMIN_PASSWORD}" \
    MOODLE_ADMIN_EMAIL="${MOODLE_ADMIN_EMAIL}" \
    MOODLE_URL="${MOODLE_URL}" >/dev/null
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

TERRAFORM_DIR="${REPO_ROOT}/terraform"
K8S_DIR="${REPO_ROOT}/k8s"
AWS_REGION=""
ODOO_DB_USER="odoo_admin"
ODOO_IMAGE=""
ODOO_DB_PASSWORD=""
MOODLE_DB_USER="moodle_admin"
MOODLE_DB_PASSWORD=""
MOODLE_DB_NAME="moodledb"
MOODLE_IMAGE="ellakcy/moodle:mysql_maria_apache_latest"
MOODLE_ADMIN_USER="admin"
MOODLE_ADMIN_PASSWORD="Admin~1234"
MOODLE_ADMIN_EMAIL="admin@esmos.meals.sg"
MOODLE_URL="http://moodle.internal.esm.local"
OSTICKET_IMAGE="$(read_dotenv_value OSTICKET_IMAGE)"
OSTICKET_DB_HOST="$(read_dotenv_value OSTICKET_DB_HOST)"
OSTICKET_DB_USER="$(read_dotenv_value OSTICKET_DB_USER)"
if [[ -z "${OSTICKET_DB_USER}" ]]; then
  OSTICKET_DB_USER="moodle_admin"
fi
OSTICKET_DB_PASSWORD=""
OSTICKET_DB_NAME="$(read_dotenv_value OSTICKET_DB_NAME)"
if [[ -z "${OSTICKET_DB_NAME}" ]]; then
  OSTICKET_DB_NAME="osticketdb"
fi
OSTICKET_INSTALL_SECRET="$(read_dotenv_value INSTALL_SECRET)"
if [[ -z "${OSTICKET_INSTALL_SECRET}" ]]; then
  OSTICKET_INSTALL_SECRET="put-a-long-random-string-here-please-change-me"
fi
OSTICKET_INSTALL_NAME="$(read_dotenv_value INSTALL_NAME)"
if [[ -z "${OSTICKET_INSTALL_NAME}" ]]; then
  OSTICKET_INSTALL_NAME="My Helpdesk"
fi
OSTICKET_INSTALL_URL="$(read_dotenv_value INSTALL_URL)"
if [[ -z "${OSTICKET_INSTALL_URL}" ]]; then
  OSTICKET_INSTALL_URL="http://osticket.internal.esm.local"
fi
OSTICKET_INSTALL_EMAIL="$(read_dotenv_value INSTALL_EMAIL)"
if [[ -z "${OSTICKET_INSTALL_EMAIL}" ]]; then
  OSTICKET_INSTALL_EMAIL="helpdesk@example.com"
fi
OSTICKET_ADMIN_FIRSTNAME="$(read_dotenv_value ADMIN_FIRSTNAME)"
if [[ -z "${OSTICKET_ADMIN_FIRSTNAME}" ]]; then
  OSTICKET_ADMIN_FIRSTNAME="Admin"
fi
OSTICKET_ADMIN_LASTNAME="$(read_dotenv_value ADMIN_LASTNAME)"
if [[ -z "${OSTICKET_ADMIN_LASTNAME}" ]]; then
  OSTICKET_ADMIN_LASTNAME="User"
fi
OSTICKET_ADMIN_EMAIL="$(read_dotenv_value ADMIN_EMAIL)"
if [[ -z "${OSTICKET_ADMIN_EMAIL}" ]]; then
  OSTICKET_ADMIN_EMAIL="admin@example.com"
fi
OSTICKET_ADMIN_USERNAME="$(read_dotenv_value ADMIN_USERNAME)"
if [[ -z "${OSTICKET_ADMIN_USERNAME}" ]]; then
  OSTICKET_ADMIN_USERNAME="ostadmin"
fi
OSTICKET_ADMIN_PASSWORD="$(read_dotenv_value ADMIN_PASSWORD)"
if [[ -z "${OSTICKET_ADMIN_PASSWORD}" ]]; then
  OSTICKET_ADMIN_PASSWORD="ChangeThisAdminPassword123!"
fi
OSTICKET_CRON_INTERVAL="$(read_dotenv_value CRON_INTERVAL)"
if [[ -z "${OSTICKET_CRON_INTERVAL}" ]]; then
  OSTICKET_CRON_INTERVAL="5"
fi
ODOO_SECRET_ID="esm/prod/odoo-db-password"
MOODLE_SECRET_ID="esm/prod/moodle-db-password"
OSTICKET_SECRET_ID="esm/prod/osticket-db-password"
KEEP_RENDERED_MANIFESTS="false"
PROVISION_INFRA="false"
SKIP_ODOO_ROLLOUT_WAIT="false"
SKIP_K8S_SECRETS_MANIFEST="true"
RENDER_ONLY="false"
RENDER_OUTPUT_DIR=""
RENDER_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --terraform-dir)
      TERRAFORM_DIR="$2"
      shift 2
      ;;
    --aws-region)
      AWS_REGION="$2"
      shift 2
      ;;
    --odoo-db-user)
      ODOO_DB_USER="$2"
      shift 2
      ;;
    --odoo-image)
      ODOO_IMAGE="$2"
      shift 2
      ;;
    --odoo-db-password)
      ODOO_DB_PASSWORD="$2"
      shift 2
      ;;
    --moodle-db-user)
      MOODLE_DB_USER="$2"
      shift 2
      ;;
    --moodle-db-password)
      MOODLE_DB_PASSWORD="$2"
      shift 2
      ;;
    --moodle-db-name)
      MOODLE_DB_NAME="$2"
      shift 2
      ;;
    --moodle-image)
      MOODLE_IMAGE="$2"
      shift 2
      ;;
    --moodle-admin-user)
      MOODLE_ADMIN_USER="$2"
      shift 2
      ;;
    --moodle-admin-password)
      MOODLE_ADMIN_PASSWORD="$2"
      shift 2
      ;;
    --moodle-admin-email)
      MOODLE_ADMIN_EMAIL="$2"
      shift 2
      ;;
    --moodle-url)
      MOODLE_URL="$2"
      shift 2
      ;;
    --osticket-image)
      OSTICKET_IMAGE="$2"
      shift 2
      ;;
    --osticket-db-host)
      OSTICKET_DB_HOST="$2"
      shift 2
      ;;
    --osticket-db-user)
      OSTICKET_DB_USER="$2"
      shift 2
      ;;
    --osticket-db-password)
      OSTICKET_DB_PASSWORD="$2"
      shift 2
      ;;
    --osticket-db-name)
      OSTICKET_DB_NAME="$2"
      shift 2
      ;;
    --osticket-install-secret)
      OSTICKET_INSTALL_SECRET="$2"
      shift 2
      ;;
    --osticket-install-name)
      OSTICKET_INSTALL_NAME="$2"
      shift 2
      ;;
    --osticket-install-url)
      OSTICKET_INSTALL_URL="$2"
      shift 2
      ;;
    --osticket-install-email)
      OSTICKET_INSTALL_EMAIL="$2"
      shift 2
      ;;
    --osticket-admin-firstname)
      OSTICKET_ADMIN_FIRSTNAME="$2"
      shift 2
      ;;
    --osticket-admin-lastname)
      OSTICKET_ADMIN_LASTNAME="$2"
      shift 2
      ;;
    --osticket-admin-email)
      OSTICKET_ADMIN_EMAIL="$2"
      shift 2
      ;;
    --osticket-admin-username)
      OSTICKET_ADMIN_USERNAME="$2"
      shift 2
      ;;
    --osticket-admin-password)
      OSTICKET_ADMIN_PASSWORD="$2"
      shift 2
      ;;
    --osticket-cron-interval)
      OSTICKET_CRON_INTERVAL="$2"
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
    --keep-rendered-manifests)
      KEEP_RENDERED_MANIFESTS="true"
      shift
      ;;
    --skip-odoo-rollout-wait)
      SKIP_ODOO_ROLLOUT_WAIT="true"
      shift
      ;;
    --include-k8s-secrets-manifest)
      SKIP_K8S_SECRETS_MANIFEST="false"
      shift
      ;;
    --render-only)
      RENDER_ONLY="true"
      shift
      ;;
    --render-output-dir)
      RENDER_OUTPUT_DIR="$2"
      shift 2
      ;;
    --provision-infra)
      PROVISION_INFRA="true"
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
if [[ -n "${RENDER_OUTPUT_DIR}" && "${RENDER_OUTPUT_DIR}" != /* ]]; then
  RENDER_OUTPUT_DIR="${REPO_ROOT}/${RENDER_OUTPUT_DIR}"
fi

cleanup() {
  if [[ -n "${RENDER_DIR}" && -d "${RENDER_DIR}" && "${KEEP_RENDERED_MANIFESTS}" != "true" ]]; then
    rm -rf "${RENDER_DIR}"
  fi
}

trap cleanup EXIT

require_cmd terraform
require_cmd aws
require_cmd kubectl
require_cmd perl

if [[ "${PROVISION_INFRA}" == "true" ]]; then
  echo "Provisioning infrastructure with Terraform..."
  terraform -chdir="${TERRAFORM_DIR}" init
  terraform -chdir="${TERRAFORM_DIR}" apply -auto-approve
fi

echo "Reading Terraform outputs..."
CLUSTER_NAME="$(tf_output_raw eks_cluster_name)"
CLUSTER_AUTOSCALER_ROLE_ARN="$(tf_output_raw eks_cluster_autoscaler_role_arn)"
EKS_NODE_GROUP_ASG_NAME="$(tf_output_raw eks_node_group_autoscaling_group_name)"
EKS_NODE_COUNT_MIN="$(tf_output_raw eks_node_count_min)"
EKS_NODE_COUNT_MAX="$(tf_output_raw eks_node_count_max)"
ODOO_DB_ENDPOINT="$(tf_output_raw odoo_rds_endpoint)"
MOODLE_DB_ENDPOINT="$(tf_output_raw moodle_rds_endpoint)"
ODOO_DB_NAME="$(tf_output_raw odoo_db_name)"
EFS_ID="$(tf_output_raw efs_id)"
EFS_ACCESS_POINT_ID="$(tf_output_raw efs_odoo_access_point_id)"

ODOO_DB_HOST="${ODOO_DB_ENDPOINT%%:*}"
MOODLE_DB_HOST="${MOODLE_DB_ENDPOINT%%:*}"
if [[ -z "${OSTICKET_DB_HOST}" || "${OSTICKET_DB_HOST}" == "osticket-db" ]]; then
  if [[ "${OSTICKET_DB_HOST}" == "osticket-db" ]]; then
    echo "Info: OSTICKET_DB_HOST=osticket-db is a docker-compose host; switching to Moodle RDS host for Kubernetes."
  fi
  OSTICKET_DB_HOST="${MOODLE_DB_HOST}"
fi

if [[ -z "${AWS_REGION}" ]]; then
  AWS_REGION="$(tf_output_raw aws_region)"
fi

if [[ -n "${ODOO_SECRET_ID}" ]]; then
  ODOO_DB_PASSWORD="$(aws --region "${AWS_REGION}" secretsmanager get-secret-value --secret-id "${ODOO_SECRET_ID}" --query SecretString --output text)"
fi
if [[ -n "${MOODLE_SECRET_ID}" ]]; then
  MOODLE_DB_PASSWORD="$(aws --region "${AWS_REGION}" secretsmanager get-secret-value --secret-id "${MOODLE_SECRET_ID}" --query SecretString --output text)"
fi
if [[ -n "${OSTICKET_SECRET_ID}" ]]; then
  OSTICKET_DB_PASSWORD="$(aws --region "${AWS_REGION}" secretsmanager get-secret-value --secret-id "${OSTICKET_SECRET_ID}" --query SecretString --output text)"
fi

if [[ "${OSTICKET_DB_USER}" == "${MOODLE_DB_USER}" ]]; then
  if [[ -n "${OSTICKET_SECRET_ID}" || -n "${OSTICKET_DB_PASSWORD}" ]]; then
    echo "Info: OSTICKET_DB_USER matches MOODLE_DB_USER (${MOODLE_DB_USER}); forcing osTicket DB password to Moodle DB password."
  fi
  OSTICKET_DB_PASSWORD="${MOODLE_DB_PASSWORD}"
elif [[ -z "${OSTICKET_DB_PASSWORD}" ]]; then
  OSTICKET_DB_PASSWORD="${MOODLE_DB_PASSWORD}"
fi

if [[ -z "${ODOO_DB_PASSWORD}" || -z "${MOODLE_DB_PASSWORD}" ]]; then
  echo "Error: provide passwords with --*-db-password or Secret IDs with --odoo-secret-id/--moodle-secret-id." >&2
  usage
  exit 1
fi

echo "Updating kubeconfig for cluster ${CLUSTER_NAME} in ${AWS_REGION}..."
if [[ "${RENDER_ONLY}" != "true" ]]; then
  aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null
fi

# If no --odoo-image was passed, reuse the image already running in the cluster.
# If the cluster has no deployment yet, fall back to the ECR image that
# deploy-odoo-image-to-eks.sh pushes (SOURCE_IMAGE=odoo17-custom:latest → esm/odoo17).
if [[ -z "${ODOO_IMAGE}" ]]; then
  ODOO_IMAGE="$(kubectl get deployment odoo-private -n odoo-private \
    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
fi
if [[ -z "${ODOO_IMAGE}" || "${ODOO_IMAGE}" == *":latest" ]]; then
  _ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  ODOO_IMAGE="$(resolve_latest_ecr_image "${_ACCOUNT_ID}" "${AWS_REGION}" "esm/odoo17" || true)"
  if [[ -z "${ODOO_IMAGE}" ]]; then
    echo "Error: unable to resolve latest tagged Odoo image from ECR repo 'esm/odoo17'." >&2
    echo "Pass --odoo-image explicitly, or push a tagged image first." >&2
    exit 1
  fi
  unset _ACCOUNT_ID
fi
echo "Using Odoo image: ${ODOO_IMAGE}"

# If no --osticket-image was passed, reuse the running image or resolve from ECR.
if [[ -z "${OSTICKET_IMAGE}" && "${RENDER_ONLY}" != "true" ]]; then
  OSTICKET_IMAGE="$(kubectl get deployment osticket -n osticket-private \
    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
fi
if [[ -z "${OSTICKET_IMAGE}" || "${OSTICKET_IMAGE}" == *":latest" ]]; then
  _ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  OSTICKET_IMAGE="$(resolve_latest_ecr_image "${_ACCOUNT_ID}" "${AWS_REGION}" "esm/osticket" || true)"
  unset _ACCOUNT_ID
fi
if [[ -z "${OSTICKET_IMAGE}" ]]; then
  echo "Error: unable to resolve osTicket image. Pass --osticket-image explicitly or push a tagged image to esm/osticket in ECR." >&2
  exit 1
fi
echo "Using osTicket image: ${OSTICKET_IMAGE}"

RENDER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/esm-k8s-XXXXXXXX")"
cp -R "${K8S_DIR}/." "${RENDER_DIR}/"

if [[ "${SKIP_K8S_SECRETS_MANIFEST}" == "true" ]]; then
  if [[ -f "${RENDER_DIR}/kustomization.yaml" ]]; then
    perl -0777 -i -pe 's/^\s*-\s*secrets\.yaml\s*$//mg' "${RENDER_DIR}/kustomization.yaml"
  fi
  rm -f "${RENDER_DIR}/secrets.yaml"
fi

echo "Rendering manifests with current Terraform outputs..."
export ODOO_DB_HOST ODOO_DB_USER ODOO_DB_PASSWORD
export ODOO_IMAGE
export ODOO_DB_NAME
export MOODLE_DB_HOST MOODLE_DB_USER MOODLE_DB_NAME MOODLE_DB_PASSWORD
export MOODLE_IMAGE MOODLE_ADMIN_USER MOODLE_ADMIN_PASSWORD MOODLE_ADMIN_EMAIL MOODLE_URL
export OSTICKET_IMAGE
export OSTICKET_DB_HOST OSTICKET_DB_USER OSTICKET_DB_NAME OSTICKET_DB_PASSWORD
export OSTICKET_INSTALL_SECRET OSTICKET_INSTALL_NAME OSTICKET_INSTALL_URL OSTICKET_INSTALL_EMAIL
export OSTICKET_ADMIN_FIRSTNAME OSTICKET_ADMIN_LASTNAME OSTICKET_ADMIN_EMAIL OSTICKET_ADMIN_USERNAME OSTICKET_ADMIN_PASSWORD
export OSTICKET_CRON_INTERVAL
export EFS_ID EFS_ACCESS_POINT_ID
export CLUSTER_NAME CLUSTER_AUTOSCALER_ROLE_ARN EKS_NODE_GROUP_ASG_NAME
export EKS_NODE_COUNT_MIN EKS_NODE_COUNT_MAX

while IFS= read -r -d '' file; do
  perl -0777 -i -pe '
    s/__ODOO_DB_HOST__/$ENV{ODOO_DB_HOST}/g;
    s/__ODOO_DB_USER__/$ENV{ODOO_DB_USER}/g;
    s/__ODOO_DB_PASSWORD__/$ENV{ODOO_DB_PASSWORD}/g;
    s#__ODOO_IMAGE__#$ENV{ODOO_IMAGE}#g;
    s/__ODOO_DB_NAME__/$ENV{ODOO_DB_NAME}/g;
    s/__MOODLE_DB_HOST__/$ENV{MOODLE_DB_HOST}/g;
    s/__MOODLE_DB_USER__/$ENV{MOODLE_DB_USER}/g;
    s/__MOODLE_DB_NAME__/$ENV{MOODLE_DB_NAME}/g;
    s/__MOODLE_DB_PASSWORD__/$ENV{MOODLE_DB_PASSWORD}/g;
    s#__MOODLE_IMAGE__#$ENV{MOODLE_IMAGE}#g;
    s/__MOODLE_ADMIN_USER__/$ENV{MOODLE_ADMIN_USER}/g;
    s/__MOODLE_ADMIN_PASSWORD__/$ENV{MOODLE_ADMIN_PASSWORD}/g;
    s/__MOODLE_ADMIN_EMAIL__/$ENV{MOODLE_ADMIN_EMAIL}/g;
    s#__MOODLE_URL__#$ENV{MOODLE_URL}#g;
    s#__OSTICKET_IMAGE__#$ENV{OSTICKET_IMAGE}#g;
    s/__OSTICKET_DB_HOST__/$ENV{OSTICKET_DB_HOST}/g;
    s/__OSTICKET_DB_USER__/$ENV{OSTICKET_DB_USER}/g;
    s/__OSTICKET_DB_NAME__/$ENV{OSTICKET_DB_NAME}/g;
    s/__OSTICKET_DB_PASSWORD__/$ENV{OSTICKET_DB_PASSWORD}/g;
    s#__OSTICKET_INSTALL_SECRET__#$ENV{OSTICKET_INSTALL_SECRET}#g;
    s#__OSTICKET_INSTALL_NAME__#$ENV{OSTICKET_INSTALL_NAME}#g;
    s#__OSTICKET_INSTALL_URL__#$ENV{OSTICKET_INSTALL_URL}#g;
    s#__OSTICKET_INSTALL_EMAIL__#$ENV{OSTICKET_INSTALL_EMAIL}#g;
    s#__OSTICKET_ADMIN_FIRSTNAME__#$ENV{OSTICKET_ADMIN_FIRSTNAME}#g;
    s#__OSTICKET_ADMIN_LASTNAME__#$ENV{OSTICKET_ADMIN_LASTNAME}#g;
    s#__OSTICKET_ADMIN_EMAIL__#$ENV{OSTICKET_ADMIN_EMAIL}#g;
    s#__OSTICKET_ADMIN_USERNAME__#$ENV{OSTICKET_ADMIN_USERNAME}#g;
    s#__OSTICKET_ADMIN_PASSWORD__#$ENV{OSTICKET_ADMIN_PASSWORD}#g;
    s#__OSTICKET_CRON_INTERVAL__#$ENV{OSTICKET_CRON_INTERVAL}#g;
    s/__EFS_ID__/$ENV{EFS_ID}/g;
    s/__EFS_ACCESS_POINT_ID__/$ENV{EFS_ACCESS_POINT_ID}/g;
    s/__CLUSTER_NAME__/$ENV{CLUSTER_NAME}/g;
    s/__CLUSTER_AUTOSCALER_ROLE_ARN__/$ENV{CLUSTER_AUTOSCALER_ROLE_ARN}/g;
    s/__EKS_NODE_GROUP_ASG_NAME__/$ENV{EKS_NODE_GROUP_ASG_NAME}/g;
    s/__EKS_NODE_COUNT_MIN__/$ENV{EKS_NODE_COUNT_MIN}/g;
    s/__EKS_NODE_COUNT_MAX__/$ENV{EKS_NODE_COUNT_MAX}/g;
  ' "$file"
done < <(find "${RENDER_DIR}" -type f \( -name "*.yaml" -o -name "*.yml" \) -print0)

if grep -R --line-number "__[A-Z0-9_]\+__" "${RENDER_DIR}" >/dev/null; then
  echo "Error: unresolved placeholders found in rendered manifests." >&2
  grep -R --line-number "__[A-Z0-9_]\+__" "${RENDER_DIR}" >&2
  exit 1
fi

if [[ -n "${RENDER_OUTPUT_DIR}" ]]; then
  rm -rf "${RENDER_OUTPUT_DIR}"
  mkdir -p "${RENDER_OUTPUT_DIR}"
  cp -R "${RENDER_DIR}/." "${RENDER_OUTPUT_DIR}/"
  echo "Rendered manifests written to: ${RENDER_OUTPUT_DIR}"
fi

if [[ "${RENDER_ONLY}" == "true" ]]; then
  if [[ -z "${RENDER_OUTPUT_DIR}" ]]; then
    echo "Render-only complete. Use --render-output-dir to persist artifacts."
  fi
  exit 0
fi

echo "Applying Kubernetes manifests..."
kubectl apply -k "${RENDER_DIR}"

repair_live_moodle_placeholder_env_if_needed

echo "Restarting deployments..."
kubectl rollout restart deployment/odoo-private -n odoo-private
kubectl rollout restart deployment/odoo-private-gateway -n odoo-private
kubectl rollout restart deployment/odoo-public -n odoo-public
kubectl rollout restart deployment/moodle -n moodle-private
kubectl rollout restart deployment/osticket -n osticket-private
if [[ "${SKIP_ODOO_ROLLOUT_WAIT}" != "true" ]]; then
  kubectl rollout status deployment/odoo-private -n odoo-private --timeout=300s
  kubectl rollout status deployment/odoo-private-gateway -n odoo-private --timeout=300s
  kubectl rollout status deployment/odoo-public -n odoo-public --timeout=300s
else
  echo "Skipping Odoo rollout wait (bootstrap expected to run afterwards)."
fi
kubectl rollout status deployment/moodle -n moodle-private --timeout=300s
kubectl rollout status deployment/osticket -n osticket-private --timeout=300s

ensure_moodle_db_is_complete

echo "Current pod status:"
kubectl get pods -n odoo-public
kubectl get pods -n odoo-private
kubectl get pods -n moodle-private
kubectl get pods -n osticket-private

if [[ "${KEEP_RENDERED_MANIFESTS}" == "true" ]]; then
  echo "Rendered manifests kept at: ${RENDER_DIR}"
fi

echo "Done."
