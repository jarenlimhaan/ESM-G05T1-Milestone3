#!/usr/bin/env bash
# deploy-odoo-image-to-eks.sh
#
# Build/push the custom Odoo image to ECR, then run one-time data-bootstrap
# tasks (DB restore, filestore sync, module upgrade) on EKS.
#
# Prerequisites
#   1. ArgoCD has synced all workload Applications (namespaces + PVCs exist).
#   2. AWS CLI is authenticated (env vars, IAM role, or SSO profile).
#   3. Docker daemon is running (unless --skip-image-push).
#
# Run with --help to see all flags.
set -euo pipefail

# ─── CONSTANTS ────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ─── USAGE ────────────────────────────────────────────────────────────────────

usage() {
  cat <<'EOF'
Build/push a local Odoo image to ECR, then run one-time data bootstrap tasks.

Kubernetes deployment is handled by ArgoCD (bootstrap.yaml). Run this script
AFTER ArgoCD has synced all workload Applications (namespaces and PVCs must
already exist).

Usage:
  ./scripts/deploy-odoo-image-to-eks.sh [flags]

Image flags:
  --source-image <image>          Local Docker image to push  [odoo17-custom:latest]
  --ecr-repo-name <name>          ECR repository name         [esm/odoo17]
  --image-tag <tag>               Tag for the pushed image    [YYYYMMDD-HHmmss]
  --target-image <ref>            Full image ref (overrides registry/repo/tag)

Infrastructure flags:
  --terraform-dir <path>          Path to terraform directory [./terraform]
  --aws-region <region>           AWS region                  [from terraform output]

Database flags (Odoo — PostgreSQL):
  --odoo-db-user <user>           Odoo RDS superuser          [odoo_admin]
  --odoo-secret-id <id>           Secrets Manager ID for Odoo DB password
                                  [esm/prod/odoo-db-password]

Database flags (Moodle/osTicket — shared MySQL):
  --moodle-secret-id <id>         Secrets Manager ID for Moodle DB password
                                  [esm/prod/moodle-db-password]
  --moodle-db-name <name>         Moodle database name        [moodledb]
  --osticket-db-name <name>       osTicket database name      [osticketdb]
  --osticket-db-user <user>       osTicket DB user            [moodle_admin]
  --osticket-image <ref>          Full image ref for osTicket (resolved from ECR if omitted)

File paths:
  --sql-dump-file <path>          Odoo SQL dump               [data/odoo17/odoo.sql.gz]
  --moodle-sql-dump-file <path>   Moodle SQL dump             [data/moodle-course-backup.mbz]
  --osticket-sql-dump-file <path> osTicket SQL dump           [data/osticket/osticket.sql.gz]
  --filestore-dir <path>          Odoo filestore directory    [filestore/odoo]

Skip flags (all default to false):
  --skip-image-push               Skip Docker build/push to ECR
  --skip-deploy                   Skip ECR image resolution (ArgoCD already deployed)
  --skip-db-restore               Skip Odoo DB restore
  --skip-osticket-db-restore      Skip osTicket DB restore
  --skip-moodle-db-restore        Skip Moodle DB restore
  --skip-filestore-sync           Skip Odoo filestore → EFS sync
  --skip-module-upgrade           Skip Odoo module upgrade job

Other:
  --provision-infra               Run terraform apply before bootstrap (rare)
  -h|--help                       Show this help
EOF
}

# ─── HELPERS ──────────────────────────────────────────────────────────────────

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Error: required command '$1' not found." >&2; exit 1; }
}

# Read a key=value pair from .env (if the file exists). Outputs nothing when
# the file or key is absent. Never fails.
read_dotenv_value() {
  local key="$1"
  local env_file="${REPO_ROOT}/.env"
  [[ -f "${env_file}" ]] || return 0
  local line
  line="$(grep -E "^${key}=" "${env_file}" | tail -n 1 || true)"
  [[ -n "${line}" ]] && printf '%s' "${line#*=}" | tr -d '\r'
}

# Return the most-recently-pushed image tag from an ECR repository, or empty.
resolve_latest_ecr_tag() {
  local region="$1"
  local repo_name="$2"
  aws ecr describe-images \
    --region "${region}" \
    --repository-name "${repo_name}" \
    --query "reverse(sort_by(imageDetails[?imageTags!=null], &imagePushedAt))[0].imageTags[0]" \
    --output text 2>/dev/null || true
}

# ─── DEFAULTS ─────────────────────────────────────────────────────────────────

SOURCE_IMAGE="odoo17-custom:latest"
ECR_REPO_NAME="esm/odoo17"
IMAGE_TAG="$(date +%Y%m%d-%H%M%S)"
TARGET_IMAGE=""

TERRAFORM_DIR="${REPO_ROOT}/terraform"
AWS_REGION=""

ODOO_DB_USER="odoo_admin"
ODOO_SECRET_ID="esm/prod/odoo-db-password"

MOODLE_DB_USER="moodle_admin"
MOODLE_DB_NAME="moodledb"
MOODLE_SECRET_ID="esm/prod/moodle-db-password"

OSTICKET_DB_NAME="osticketdb"
OSTICKET_SECRET_ID=""
OSTICKET_IMAGE=""

# Allow .env to override DB names, users, and Secrets Manager IDs.
_v="$(read_dotenv_value OSTICKET_DB_USER)";  OSTICKET_DB_USER="${_v:-moodle_admin}"
_v="$(read_dotenv_value OSTICKET_DB_NAME)";  [[ -n "${_v}" ]] && OSTICKET_DB_NAME="${_v}"
_v="$(read_dotenv_value OSTICKET_IMAGE)";    [[ -n "${_v}" ]] && OSTICKET_IMAGE="${_v}"
_v="$(read_dotenv_value ODOO_DB_SECRET_ID)"; [[ -n "${_v}" ]] && ODOO_SECRET_ID="${_v}"
_v="$(read_dotenv_value MOODLE_DB_SECRET_ID)"; [[ -n "${_v}" ]] && MOODLE_SECRET_ID="${_v}"
_v="$(read_dotenv_value OSTICKET_DB_SECRET_ID)"; [[ -n "${_v}" ]] && OSTICKET_SECRET_ID="${_v}"
unset _v

SQL_DUMP_FILE="${REPO_ROOT}/data/odoo17/odoo.sql.gz"
MOODLE_SQL_DUMP_FILE="${REPO_ROOT}/data/moodle-course-backup.mbz"
OSTICKET_SQL_DUMP_FILE="${REPO_ROOT}/data/osticket/osticket.sql.gz"
FILESTORE_DIR="${REPO_ROOT}/filestore/odoo"
MODULE_UPGRADE_LIST="helpdesk_mgmt,helpdesk_mgmt_merge,helpdesk_mgmt_project,helpdesk_mgmt_sale,helpdesk_ticket_related,helpdesk_type"

SKIP_IMAGE_PUSH="false"
SKIP_DEPLOY="false"
SKIP_DB_RESTORE="false"
SKIP_OSTICKET_DB_RESTORE="false"
SKIP_MOODLE_DB_RESTORE="false"
SKIP_FILESTORE_SYNC="false"
SKIP_MODULE_UPGRADE="false"
PROVISION_INFRA="false"
ODOO_SCALED_DOWN="false"
OSTICKET_SCALED_DOWN="false"
MOODLE_SCALED_DOWN="false"

# ─── FAILURE RECOVERY ─────────────────────────────────────────────────────────

# If the script exits non-zero mid-bootstrap, restore any deployments that were
# scaled to zero so workloads are not left permanently unavailable.
restore_scaled_workloads_on_failure() {
  local exit_code=$?
  [[ "${exit_code}" -eq 0 ]] && return 0
  echo "Bootstrap failed (exit ${exit_code}). Attempting workload restore..." >&2
  [[ "${ODOO_SCALED_DOWN}" == "true" ]] && {
    kubectl scale deployment/odoo-private -n odoo-private --replicas=1 >/dev/null 2>&1 || true
    kubectl scale deployment/odoo-public  -n odoo-public  --replicas=1 >/dev/null 2>&1 || true
  }
  [[ "${OSTICKET_SCALED_DOWN}" == "true" ]] && \
    kubectl scale deployment/osticket -n osticket-private --replicas=1 >/dev/null 2>&1 || true
  [[ "${MOODLE_SCALED_DOWN}" == "true" ]] && \
    kubectl scale deployment/moodle -n moodle-private --replicas=1 >/dev/null 2>&1 || true
}
trap restore_scaled_workloads_on_failure EXIT

# ─── ARGUMENT PARSING ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-image)             SOURCE_IMAGE="$2";              shift 2 ;;
    --ecr-repo-name)            ECR_REPO_NAME="$2";             shift 2 ;;
    --image-tag)                IMAGE_TAG="$2";                 shift 2 ;;
    --target-image)             TARGET_IMAGE="$2";              shift 2 ;;
    --terraform-dir)            TERRAFORM_DIR="$2";             shift 2 ;;
    --aws-region)               AWS_REGION="$2";                shift 2 ;;
    --odoo-db-user)             ODOO_DB_USER="$2";              shift 2 ;;
    --odoo-secret-id)           ODOO_SECRET_ID="$2";            shift 2 ;;
    --moodle-secret-id)         MOODLE_SECRET_ID="$2";          shift 2 ;;
    --moodle-db-name)           MOODLE_DB_NAME="$2";            shift 2 ;;
    --osticket-db-user)         OSTICKET_DB_USER="$2";          shift 2 ;;
    --osticket-db-name)         OSTICKET_DB_NAME="$2";          shift 2 ;;
    --osticket-secret-id)       OSTICKET_SECRET_ID="$2";        shift 2 ;;
    --osticket-image)           OSTICKET_IMAGE="$2";            shift 2 ;;
    --sql-dump-file)            SQL_DUMP_FILE="$2";             shift 2 ;;
    --osticket-sql-dump-file)   OSTICKET_SQL_DUMP_FILE="$2";    shift 2 ;;
    --moodle-sql-dump-file)     MOODLE_SQL_DUMP_FILE="$2";      shift 2 ;;
    --filestore-dir)            FILESTORE_DIR="$2";             shift 2 ;;
    --skip-image-push)          SKIP_IMAGE_PUSH="true";         shift   ;;
    --skip-deploy)              SKIP_DEPLOY="true";             shift   ;;
    --skip-db-restore)          SKIP_DB_RESTORE="true";         shift   ;;
    --skip-osticket-db-restore) SKIP_OSTICKET_DB_RESTORE="true"; shift  ;;
    --skip-moodle-db-restore)   SKIP_MOODLE_DB_RESTORE="true";  shift   ;;
    --skip-filestore-sync)      SKIP_FILESTORE_SYNC="true";     shift   ;;
    --skip-module-upgrade)      SKIP_MODULE_UPGRADE="true";     shift   ;;
    --provision-infra)          PROVISION_INFRA="true";         shift   ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

# Normalise relative paths to absolute.
[[ "${TERRAFORM_DIR}"          != /* ]] && TERRAFORM_DIR="${REPO_ROOT}/${TERRAFORM_DIR}"
[[ "${SQL_DUMP_FILE}"          != /* ]] && SQL_DUMP_FILE="${REPO_ROOT}/${SQL_DUMP_FILE}"
[[ "${OSTICKET_SQL_DUMP_FILE}" != /* ]] && OSTICKET_SQL_DUMP_FILE="${REPO_ROOT}/${OSTICKET_SQL_DUMP_FILE}"
[[ "${MOODLE_SQL_DUMP_FILE}"   != /* ]] && MOODLE_SQL_DUMP_FILE="${REPO_ROOT}/${MOODLE_SQL_DUMP_FILE}"
[[ "${FILESTORE_DIR}"          != /* ]] && FILESTORE_DIR="${REPO_ROOT}/${FILESTORE_DIR}"

# ─── PREREQUISITES ────────────────────────────────────────────────────────────

require_cmd terraform
require_cmd aws
require_cmd kubectl
[[ "${SKIP_IMAGE_PUSH}" != "true" ]] && require_cmd docker

# Validate data files exist before touching any infrastructure.
[[ "${SKIP_DB_RESTORE}"          != "true" && ! -f "${SQL_DUMP_FILE}" ]] && \
  { echo "Error: Odoo SQL dump not found: ${SQL_DUMP_FILE}" >&2; exit 1; }
[[ "${SKIP_OSTICKET_DB_RESTORE}" != "true" && ! -f "${OSTICKET_SQL_DUMP_FILE}" ]] && \
  { echo "Error: osTicket SQL dump not found: ${OSTICKET_SQL_DUMP_FILE}" >&2; exit 1; }
[[ "${SKIP_MOODLE_DB_RESTORE}"   != "true" && ! -f "${MOODLE_SQL_DUMP_FILE}" ]] && \
  { echo "Error: Moodle SQL dump not found: ${MOODLE_SQL_DUMP_FILE}" >&2; exit 1; }
[[ "${SKIP_FILESTORE_SYNC}"      != "true" && ! -d "${FILESTORE_DIR}" ]] && \
  { echo "Error: Filestore directory not found: ${FILESTORE_DIR}" >&2; exit 1; }

# ─── PHASE 1: PROVISION INFRASTRUCTURE (optional) ─────────────────────────────

if [[ "${PROVISION_INFRA}" == "true" ]]; then
  echo "=== Phase 1: Provision infrastructure with Terraform ==="

  # Resolve secrets: Secrets Manager → .env → fail.
  # Passwords are kept in short-lived local vars; unset after apply.
  TF_ODOO_PW=""
  TF_MOODLE_PW=""
  TF_INSTALL_SECRET="$(read_dotenv_value INSTALL_SECRET)"
  TF_ADMIN_PW="$(read_dotenv_value ADMIN_PASSWORD)"

  [[ -n "${ODOO_SECRET_ID}" ]] && TF_ODOO_PW="$(aws --region "${AWS_REGION:-ap-southeast-1}" \
    secretsmanager get-secret-value --secret-id "${ODOO_SECRET_ID}" \
    --query SecretString --output text 2>/dev/null || true)"
  [[ -z "${TF_ODOO_PW}" ]] && TF_ODOO_PW="$(read_dotenv_value ODOO_DB_PASSWORD)"

  [[ -n "${MOODLE_SECRET_ID}" ]] && TF_MOODLE_PW="$(aws --region "${AWS_REGION:-ap-southeast-1}" \
    secretsmanager get-secret-value --secret-id "${MOODLE_SECRET_ID}" \
    --query SecretString --output text 2>/dev/null || true)"
  [[ -z "${TF_MOODLE_PW}" ]] && TF_MOODLE_PW="$(read_dotenv_value MOODLE_DB_PASSWORD)"
  # Convenience: reuse Odoo password for Moodle if both are the same account.
  [[ -z "${TF_MOODLE_PW}" && -n "${TF_ODOO_PW}" ]] && TF_MOODLE_PW="${TF_ODOO_PW}"

  _errors=0
  [[ -z "${TF_ODOO_PW}" ]]       && echo "  missing: odoo_db_password" >&2       && ((_errors++)) || true
  [[ -z "${TF_MOODLE_PW}" ]]     && echo "  missing: moodle_db_password" >&2     && ((_errors++)) || true
  [[ -z "${TF_INSTALL_SECRET}" ]] && echo "  missing: INSTALL_SECRET (.env)" >&2 && ((_errors++)) || true
  [[ -z "${TF_ADMIN_PW}" ]]       && echo "  missing: ADMIN_PASSWORD (.env)" >&2 && ((_errors++)) || true
  if [[ "${_errors}" -gt 0 ]]; then
    echo "Error: missing secrets for --provision-infra (set in .env or Secrets Manager)." >&2
    exit 1
  fi

  terraform -chdir="${TERRAFORM_DIR}" init
  # Secrets are passed via TF_VAR_ env vars — NOT as -var= CLI args — so they
  # do not appear in ps output or shell history.
  TF_VAR_odoo_db_password="${TF_ODOO_PW}" \
  TF_VAR_moodle_db_password="${TF_MOODLE_PW}" \
  TF_VAR_osticket_install_secret="${TF_INSTALL_SECRET}" \
  TF_VAR_osticket_admin_password="${TF_ADMIN_PW}" \
    terraform -chdir="${TERRAFORM_DIR}" apply -auto-approve

  unset TF_ODOO_PW TF_MOODLE_PW TF_INSTALL_SECRET TF_ADMIN_PW _errors
fi

# ─── PHASE 2: READ TERRAFORM OUTPUTS ──────────────────────────────────────────

echo "=== Phase 2: Read Terraform outputs ==="

CLUSTER_NAME="$(terraform -chdir="${TERRAFORM_DIR}" output -raw eks_cluster_name)"
ODOO_DB_ENDPOINT="$(terraform -chdir="${TERRAFORM_DIR}" output -raw odoo_rds_endpoint)"
ODOO_DB_NAME="$(terraform -chdir="${TERRAFORM_DIR}" output -raw odoo_db_name)"
MOODLE_DB_ENDPOINT="$(terraform -chdir="${TERRAFORM_DIR}" output -raw moodle_rds_endpoint)"
[[ -z "${AWS_REGION}" ]] && AWS_REGION="$(terraform -chdir="${TERRAFORM_DIR}" output -raw aws_region)"

ODOO_DB_HOST="${ODOO_DB_ENDPOINT%%:*}"
MOODLE_DB_HOST="${MOODLE_DB_ENDPOINT%%:*}"

echo "  Cluster  : ${CLUSTER_NAME}"
echo "  Region   : ${AWS_REGION}"
echo "  Odoo DB  : ${ODOO_DB_HOST} / ${ODOO_DB_NAME}"
echo "  MySQL    : ${MOODLE_DB_HOST}"

# ─── PHASE 3: AUTHENTICATE ────────────────────────────────────────────────────

echo "=== Phase 3: Authenticate ==="

echo "  Refreshing kubeconfig..."
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# ─── PHASE 4: PUSH ODOO IMAGE TO ECR ──────────────────────────────────────────

[[ -z "${TARGET_IMAGE}" ]] && TARGET_IMAGE="${ECR_REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG}"

if [[ "${SKIP_IMAGE_PUSH}" != "true" ]]; then
  echo "=== Phase 4: Push Odoo image to ECR ==="
  echo "  Validating source image: ${SOURCE_IMAGE}"
  docker image inspect "${SOURCE_IMAGE}" >/dev/null

  if ! aws ecr describe-repositories --region "${AWS_REGION}" --repository-names "${ECR_REPO_NAME}" >/dev/null 2>&1; then
    echo "  Creating ECR repository: ${ECR_REPO_NAME}"
    aws ecr create-repository --region "${AWS_REGION}" --repository-name "${ECR_REPO_NAME}" >/dev/null
  fi

  echo "  Logging into ECR..."
  aws ecr get-login-password --region "${AWS_REGION}" \
    | docker login --username AWS --password-stdin "${ECR_REGISTRY}" >/dev/null

  echo "  Tagging: ${SOURCE_IMAGE} → ${TARGET_IMAGE}"
  docker tag "${SOURCE_IMAGE}" "${TARGET_IMAGE}"
  echo "  Pushing: ${TARGET_IMAGE}"
  docker push "${TARGET_IMAGE}"
else
  echo "=== Phase 4: Skipping image push (using ${TARGET_IMAGE}) ==="
fi

# Resolve the osTicket image from ECR unless --skip-deploy or explicitly set.
if [[ -z "${OSTICKET_IMAGE}" && "${SKIP_DEPLOY}" != "true" ]]; then
  OSTICKET_LATEST_TAG="$(resolve_latest_ecr_tag "${AWS_REGION}" "esm/osticket")"
  if [[ -n "${OSTICKET_LATEST_TAG}" && "${OSTICKET_LATEST_TAG}" != "None" ]]; then
    OSTICKET_IMAGE="${ECR_REGISTRY}/esm/osticket:${OSTICKET_LATEST_TAG}"
    echo "  Resolved osTicket image: ${OSTICKET_IMAGE}"
  else
    echo "Error: no tagged osTicket image found in ECR repo 'esm/osticket'." >&2
    echo "       Push an image first, or pass --osticket-image explicitly." >&2
    exit 1
  fi
fi
[[ -n "${OSTICKET_IMAGE}" ]] && echo "  osTicket image: ${OSTICKET_IMAGE}"

# ─── PHASE 5: SCALE DOWN WORKLOADS ────────────────────────────────────────────

echo "=== Phase 5: Scale down workloads before data bootstrap ==="

if [[ "${SKIP_DB_RESTORE}" != "true" || "${SKIP_FILESTORE_SYNC}" != "true" || "${SKIP_MODULE_UPGRADE}" != "true" ]]; then
  echo "  Scaling down odoo-private, odoo-public..."
  kubectl scale deployment/odoo-private -n odoo-private --replicas=0 >/dev/null || true
  kubectl scale deployment/odoo-public  -n odoo-public  --replicas=0 >/dev/null || true
  ODOO_SCALED_DOWN="true"
fi
if [[ "${SKIP_OSTICKET_DB_RESTORE}" != "true" ]]; then
  echo "  Scaling down osticket..."
  kubectl scale deployment/osticket -n osticket-private --replicas=0 >/dev/null || true
  OSTICKET_SCALED_DOWN="true"
fi
if [[ "${SKIP_MOODLE_DB_RESTORE}" != "true" ]]; then
  echo "  Scaling down moodle..."
  kubectl scale deployment/moodle -n moodle-private --replicas=0 >/dev/null || true
  MOODLE_SCALED_DOWN="true"
fi

# ─── PHASE 6: RESTORE ODOO DATABASE ───────────────────────────────────────────

if [[ "${SKIP_DB_RESTORE}" != "true" ]]; then
  echo "=== Phase 6: Restore Odoo PostgreSQL database ==="
  POD_NAME="odoo-db-restore-$(date +%s)"
  # PGPASSWORD is injected via secretKeyRef from the odoo-db k8s secret
  # (synced from AWS Secrets Manager by ASCP). Never expanded into the command.
  echo "  Starting restore pod ${POD_NAME}..."
  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: odoo-private
spec:
  restartPolicy: Never
  containers:
    - name: postgres
      image: postgres:15
      command: ["sh", "-c", "sleep 3600"]
      env:
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: odoo-db
              key: password
EOF
  kubectl wait --for=condition=Ready "pod/${POD_NAME}" -n odoo-private --timeout=180s >/dev/null
  echo "  Uploading dump..."
  kubectl exec -i -n odoo-private "${POD_NAME}" -- sh -ceu "cat > /tmp/odoo.sql.gz" < "${SQL_DUMP_FILE}"
  echo "  Running restore..."
  kubectl exec -n odoo-private "${POD_NAME}" -- sh -ceu "
psql -h '${ODOO_DB_HOST}' -U '${ODOO_DB_USER}' -d postgres -tAc \"SELECT 1 FROM pg_roles WHERE rolname='odoo17'\" | grep -q 1 || psql -h '${ODOO_DB_HOST}' -U '${ODOO_DB_USER}' -d postgres -c \"CREATE ROLE odoo17\";
psql -h '${ODOO_DB_HOST}' -U '${ODOO_DB_USER}' -d postgres -c \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${ODOO_DB_NAME}' AND pid <> pg_backend_pid();\";
psql -h '${ODOO_DB_HOST}' -U '${ODOO_DB_USER}' -d postgres -c \"DROP DATABASE IF EXISTS ${ODOO_DB_NAME};\";
psql -h '${ODOO_DB_HOST}' -U '${ODOO_DB_USER}' -d postgres -c \"CREATE DATABASE ${ODOO_DB_NAME} OWNER ${ODOO_DB_USER};\";
gunzip -c /tmp/odoo.sql.gz | psql -h '${ODOO_DB_HOST}' -U '${ODOO_DB_USER}' -d '${ODOO_DB_NAME}';
"
  kubectl delete pod "${POD_NAME}" -n odoo-private --ignore-not-found >/dev/null
  echo "  Odoo DB restore complete."
fi

# ─── PHASE 7: SYNC ODOO FILESTORE → EFS ───────────────────────────────────────

if [[ "${SKIP_FILESTORE_SYNC}" != "true" ]]; then
  echo "=== Phase 7: Sync Odoo filestore to EFS ==="
  # odoo-private-pvc is created by ArgoCD — wait for it to be Bound.
  echo "  Waiting for odoo-private-pvc to be Bound (up to 120 s)..."
  for _i in $(seq 1 24); do
    PVC_STATUS="$(kubectl get pvc odoo-private-pvc -n odoo-private -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    if [[ "${PVC_STATUS}" == "Bound" ]]; then break; fi
    echo "    status: ${PVC_STATUS:-NotFound}"
    sleep 5
  done
  PVC_STATUS="$(kubectl get pvc odoo-private-pvc -n odoo-private -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [[ "${PVC_STATUS}" != "Bound" ]]; then
    echo "Error: odoo-private-pvc is not Bound after 120 s (${PVC_STATUS})." >&2
    echo "       Ensure ArgoCD has fully synced the odoo-private Application." >&2
    exit 1
  fi

  POD_NAME="odoo-filestore-sync-$(date +%s)"
  echo "  Starting filestore sync pod ${POD_NAME}..."
  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: odoo-private
spec:
  restartPolicy: Never
  containers:
    - name: sync
      image: alpine:3.20
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: odoo-data
          mountPath: /mnt/odoo-data
  volumes:
    - name: odoo-data
      persistentVolumeClaim:
        claimName: odoo-private-pvc
EOF
  kubectl wait --for=condition=Ready "pod/${POD_NAME}" -n odoo-private --timeout=180s >/dev/null
  echo "  Syncing via tar pipe..."
  kubectl exec -n odoo-private "${POD_NAME}" -- \
    sh -c "mkdir -p /mnt/odoo-data/filestore && rm -rf /mnt/odoo-data/filestore/${ODOO_DB_NAME}"
  tar -C "${FILESTORE_DIR}" -cf - . \
    | kubectl exec -i -n odoo-private "${POD_NAME}" -- \
        sh -ceu "mkdir -p /mnt/odoo-data/filestore/${ODOO_DB_NAME} && tar -xf - -C /mnt/odoo-data/filestore/${ODOO_DB_NAME}"
  kubectl exec -n odoo-private "${POD_NAME}" -- \
    sh -c "chown -R 101:101 /mnt/odoo-data/filestore/${ODOO_DB_NAME} || true"
  kubectl delete pod "${POD_NAME}" -n odoo-private --ignore-not-found >/dev/null
  echo "  Filestore sync complete."
fi

# ─── PHASE 8: RESTORE OSTICKET DATABASE ───────────────────────────────────────

if [[ "${SKIP_OSTICKET_DB_RESTORE}" != "true" ]]; then
  echo "=== Phase 8: Restore osTicket MySQL database ==="
  POD_NAME="osticket-db-restore-$(date +%s)"
  # MYSQL_PWD is injected via secretKeyRef from the osticket-db k8s secret
  # (synced from AWS Secrets Manager by ASCP). Never expanded into the command.
  echo "  Starting restore pod ${POD_NAME}..."
  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: osticket-private
spec:
  restartPolicy: Never
  containers:
    - name: mysql
      image: mysql:8.0
      command: ["sh", "-c", "sleep 3600"]
      env:
        - name: MYSQL_PWD
          valueFrom:
            secretKeyRef:
              name: osticket-db
              key: password
EOF
  kubectl wait --for=condition=Ready "pod/${POD_NAME}" -n osticket-private --timeout=180s >/dev/null
  echo "  Uploading dump..."
  kubectl exec -i -n osticket-private "${POD_NAME}" -- sh -ceu "cat > /tmp/osticket.sql.gz" < "${OSTICKET_SQL_DUMP_FILE}"
  echo "  Running restore..."
  kubectl exec -n osticket-private "${POD_NAME}" -- sh -ceu "
mysql -h '${MOODLE_DB_HOST}' -u '${OSTICKET_DB_USER}' -e \"DROP DATABASE IF EXISTS ${OSTICKET_DB_NAME};\";
mysql -h '${MOODLE_DB_HOST}' -u '${OSTICKET_DB_USER}' -e \"CREATE DATABASE ${OSTICKET_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\";
mysql -h '${MOODLE_DB_HOST}' -u '${OSTICKET_DB_USER}' -e \"GRANT ALL PRIVILEGES ON ${OSTICKET_DB_NAME}.* TO '${OSTICKET_DB_USER}'@'%'; FLUSH PRIVILEGES;\";
gunzip -c /tmp/osticket.sql.gz | mysql -h '${MOODLE_DB_HOST}' -u '${OSTICKET_DB_USER}' '${OSTICKET_DB_NAME}';
"
  kubectl delete pod "${POD_NAME}" -n osticket-private --ignore-not-found >/dev/null
  echo "  osTicket DB restore complete."
fi

# ─── PHASE 9: RESTORE MOODLE DATABASE ─────────────────────────────────────────

if [[ "${SKIP_MOODLE_DB_RESTORE}" != "true" ]]; then
  echo "=== Phase 9: Restore Moodle MySQL database ==="
  POD_NAME="moodle-db-restore-$(date +%s)"
  # MYSQL_PWD is injected via secretKeyRef from the moodle-db k8s secret — never
  # expanded into the command string.
  echo "  Starting restore pod ${POD_NAME}..."
  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: moodle-private
spec:
  restartPolicy: Never
  containers:
    - name: mysql
      image: mysql:8.0
      command: ["sh", "-c", "sleep 3600"]
      env:
        - name: MYSQL_PWD
          valueFrom:
            secretKeyRef:
              name: moodle-db
              key: password
EOF
  kubectl wait --for=condition=Ready "pod/${POD_NAME}" -n moodle-private --timeout=180s >/dev/null
  echo "  Uploading dump..."
  kubectl exec -i -n moodle-private "${POD_NAME}" -- sh -ceu "cat > /tmp/moodle.sql.gz" < "${MOODLE_SQL_DUMP_FILE}"
  echo "  Running restore..."
  kubectl exec -n moodle-private "${POD_NAME}" -- sh -ceu "
mysql -h '${MOODLE_DB_HOST}' -u '${MOODLE_DB_USER}' -e \"DROP DATABASE IF EXISTS ${MOODLE_DB_NAME};\";
mysql -h '${MOODLE_DB_HOST}' -u '${MOODLE_DB_USER}' -e \"CREATE DATABASE ${MOODLE_DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\";
gunzip -c /tmp/moodle.sql.gz | mysql -h '${MOODLE_DB_HOST}' -u '${MOODLE_DB_USER}' '${MOODLE_DB_NAME}';
"
  kubectl delete pod "${POD_NAME}" -n moodle-private --ignore-not-found >/dev/null
  echo "  Moodle DB restore complete."
fi

# ─── PHASE 10: ODOO MODULE UPGRADE ────────────────────────────────────────────

if [[ "${SKIP_MODULE_UPGRADE}" != "true" ]]; then
  echo "=== Phase 10: Run Odoo module upgrade ==="
  JOB_NAME="odoo-module-upgrade-$(date +%s)"
  # PASSWORD env var is read by the container from the odoo-db k8s secret.
  # \$PASSWORD below is escaped so this shell does not expand it — the
  # container's sh -lc evaluates it from the pod environment at runtime.
  echo "  Submitting job ${JOB_NAME}..."
  cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: odoo-private
spec:
  ttlSecondsAfterFinished: 3600
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: odoo-upgrade
          image: ${TARGET_IMAGE}
          command: ["sh", "-lc", "odoo --database=${ODOO_DB_NAME} --db-filter=^${ODOO_DB_NAME}$ --db_host=${ODOO_DB_HOST} --db_port=5432 --db_user=${ODOO_DB_USER} --db_password=\$PASSWORD --db_sslmode=require -u ${MODULE_UPGRADE_LIST} --stop-after-init"]
          env:
            - name: HOST
              value: "${ODOO_DB_HOST}"
            - name: PORT
              value: "5432"
            - name: USER
              value: "${ODOO_DB_USER}"
            - name: PASSWORD
              valueFrom:
                secretKeyRef:
                  name: odoo-db
                  key: password
            - name: PGSSLMODE
              value: require
EOF
  if ! kubectl wait --for=condition=complete "job/${JOB_NAME}" -n odoo-private --timeout=1800s >/dev/null; then
    echo "Error: module upgrade job failed. Last 200 log lines:" >&2
    kubectl logs "job/${JOB_NAME}" -n odoo-private --tail=200 || true
    exit 1
  fi
  kubectl logs "job/${JOB_NAME}" -n odoo-private --tail=100
  echo "  Module upgrade complete."
fi

# ─── PHASE 11: SCALE WORKLOADS BACK UP ────────────────────────────────────────

echo "=== Phase 11: Scale workloads back up ==="

if [[ "${SKIP_DB_RESTORE}" != "true" || "${SKIP_FILESTORE_SYNC}" != "true" || "${SKIP_MODULE_UPGRADE}" != "true" ]]; then
  echo "  Scaling up odoo-private, odoo-public..."
  kubectl scale deployment/odoo-private -n odoo-private --replicas=1 >/dev/null || true
  kubectl scale deployment/odoo-public  -n odoo-public  --replicas=1 >/dev/null || true
  kubectl rollout status deployment/odoo-private -n odoo-private --timeout=300s
  kubectl rollout status deployment/odoo-public  -n odoo-public  --timeout=300s
  ODOO_SCALED_DOWN="false"
fi
if [[ "${SKIP_OSTICKET_DB_RESTORE}" != "true" ]]; then
  echo "  Scaling up osticket..."
  kubectl scale deployment/osticket -n osticket-private --replicas=1 >/dev/null || true
  kubectl rollout status deployment/osticket -n osticket-private --timeout=300s
  OSTICKET_SCALED_DOWN="false"
fi
if [[ "${SKIP_MOODLE_DB_RESTORE}" != "true" ]]; then
  echo "  Scaling up moodle..."
  kubectl scale deployment/moodle -n moodle-private --replicas=1 >/dev/null || true
  kubectl rollout status deployment/moodle -n moodle-private --timeout=300s
  MOODLE_SCALED_DOWN="false"
fi

# ─── DONE ─────────────────────────────────────────────────────────────────────

echo
echo "Bootstrap complete."
echo "  Odoo image  : ${TARGET_IMAGE}"
echo "  Odoo DB     : ${ODOO_DB_HOST} / ${ODOO_DB_NAME}"
echo "  MySQL host  : ${MOODLE_DB_HOST}"
echo "  Moodle DB   : ${MOODLE_DB_NAME}"
echo "  osTicket DB : ${OSTICKET_DB_NAME}"
