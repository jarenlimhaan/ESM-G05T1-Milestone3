#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Build/push a local Odoo image to ECR, deploy to EKS, and run bootstrap tasks.

Usage:
  ./scripts/deploy-odoo-image-to-eks.sh \
    --source-image odoo17-custom:latest \
    --ecr-repo-name esm/odoo17 \
    [--target-image <registry/repo:tag>] \
    [--image-tag v20260322] \
    [--terraform-dir terraform] \
    [--aws-region ap-southeast-1] \
    [--odoo-db-user odoo_admin] \
    [--odoo-db-password "<password>" | --odoo-secret-id "<secret-id>"] \
    [--moodle-db-password "<password>" | --moodle-secret-id "<secret-id>"] \
    [--osticket-db-password "<password>" | --osticket-secret-id "<secret-id>"] \
    [--skip-image-push] \
    [--skip-deploy] \
    [--skip-db-restore] \
    [--skip-filestore-sync] \
    [--skip-module-upgrade] \
    [--sql-dump-file odoo17/odoo.sql.gz] \
    [--filestore-dir filestore/odoo] \
    [--provision-infra]

Notes:
  - This script reuses ./scripts/deploy-k8s-apps.sh for base manifest deployment.
  - DB restore is destructive for the target Odoo DB.
  - Filestore sync copies local filestore into EFS-backed PVC (odoo-private/odoo-pvc).
  - Defaults are preset for this repo, so you can run with no secret args.
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

SOURCE_IMAGE="odoo17-custom:latest"
ECR_REPO_NAME="esm/odoo17"
IMAGE_TAG="$(date +%Y%m%d-%H%M%S)"
TARGET_IMAGE=""
TERRAFORM_DIR="${REPO_ROOT}/terraform"
AWS_REGION=""
ODOO_DB_USER="odoo_admin"
ODOO_DB_PASSWORD=""
ODOO_SECRET_ID="esm/prod/odoo-db-password"
MOODLE_DB_USER="moodle_admin"
MOODLE_DB_PASSWORD=""
MOODLE_SECRET_ID="esm/prod/moodle-db-password"
OSTICKET_DB_USER="moodle_admin"
OSTICKET_DB_PASSWORD=""
OSTICKET_SECRET_ID=""

SQL_DUMP_FILE="${REPO_ROOT}/odoo17/odoo.sql.gz"
FILESTORE_DIR="${REPO_ROOT}/filestore/odoo"
MODULE_UPGRADE_LIST="helpdesk_mgmt,helpdesk_mgmt_merge,helpdesk_mgmt_project,helpdesk_mgmt_sale,helpdesk_ticket_related,helpdesk_type"

SKIP_IMAGE_PUSH="false"
SKIP_DEPLOY="false"
SKIP_DB_RESTORE="false"
SKIP_FILESTORE_SYNC="false"
SKIP_MODULE_UPGRADE="false"
PROVISION_INFRA="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-image)
      SOURCE_IMAGE="$2"
      shift 2
      ;;
    --ecr-repo-name)
      ECR_REPO_NAME="$2"
      shift 2
      ;;
    --image-tag)
      IMAGE_TAG="$2"
      shift 2
      ;;
    --target-image)
      TARGET_IMAGE="$2"
      shift 2
      ;;
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
    --odoo-db-password)
      ODOO_DB_PASSWORD="$2"
      shift 2
      ;;
    --odoo-secret-id)
      ODOO_SECRET_ID="$2"
      shift 2
      ;;
    --moodle-db-password)
      MOODLE_DB_PASSWORD="$2"
      shift 2
      ;;
    --moodle-secret-id)
      MOODLE_SECRET_ID="$2"
      shift 2
      ;;
    --osticket-db-password)
      OSTICKET_DB_PASSWORD="$2"
      shift 2
      ;;
    --osticket-secret-id)
      OSTICKET_SECRET_ID="$2"
      shift 2
      ;;
    --sql-dump-file)
      SQL_DUMP_FILE="$2"
      shift 2
      ;;
    --filestore-dir)
      FILESTORE_DIR="$2"
      shift 2
      ;;
    --skip-image-push)
      SKIP_IMAGE_PUSH="true"
      shift
      ;;
    --skip-deploy)
      SKIP_DEPLOY="true"
      shift
      ;;
    --skip-db-restore)
      SKIP_DB_RESTORE="true"
      shift
      ;;
    --skip-filestore-sync)
      SKIP_FILESTORE_SYNC="true"
      shift
      ;;
    --skip-module-upgrade)
      SKIP_MODULE_UPGRADE="true"
      shift
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
if [[ "${SQL_DUMP_FILE}" != /* ]]; then
  SQL_DUMP_FILE="${REPO_ROOT}/${SQL_DUMP_FILE}"
fi
if [[ "${FILESTORE_DIR}" != /* ]]; then
  FILESTORE_DIR="${REPO_ROOT}/${FILESTORE_DIR}"
fi

require_cmd terraform
require_cmd aws
require_cmd kubectl
if [[ "${SKIP_IMAGE_PUSH}" != "true" ]]; then
  require_cmd docker
fi

if [[ "${PROVISION_INFRA}" == "true" ]]; then
  echo "Provisioning infrastructure with Terraform..."
  "${SCRIPT_DIR}/terraform-init.sh" "${TERRAFORM_DIR}"
  terraform -chdir="${TERRAFORM_DIR}" apply -auto-approve
else
  "${SCRIPT_DIR}/terraform-init.sh" "${TERRAFORM_DIR}"
fi

if [[ "${SKIP_DB_RESTORE}" != "true" && ! -f "${SQL_DUMP_FILE}" ]]; then
  echo "Error: SQL dump not found: ${SQL_DUMP_FILE}" >&2
  exit 1
fi
if [[ "${SKIP_FILESTORE_SYNC}" != "true" && ! -d "${FILESTORE_DIR}" ]]; then
  echo "Error: filestore directory not found: ${FILESTORE_DIR}" >&2
  exit 1
fi

echo "Reading Terraform outputs..."
CLUSTER_NAME="$(terraform -chdir="${TERRAFORM_DIR}" output -raw eks_cluster_name)"
ODOO_DB_ENDPOINT="$(terraform -chdir="${TERRAFORM_DIR}" output -raw odoo_rds_endpoint)"
ODOO_DB_NAME="$(terraform -chdir="${TERRAFORM_DIR}" output -raw odoo_db_name)"
if [[ -z "${AWS_REGION}" ]]; then
  AWS_REGION="$(terraform -chdir="${TERRAFORM_DIR}" output -raw aws_region)"
fi
ODOO_DB_HOST="${ODOO_DB_ENDPOINT%%:*}"

if [[ -n "${ODOO_SECRET_ID}" ]]; then
  ODOO_DB_PASSWORD="$(aws --region "${AWS_REGION}" secretsmanager get-secret-value --secret-id "${ODOO_SECRET_ID}" --query SecretString --output text)"
fi
if [[ -n "${MOODLE_SECRET_ID}" ]]; then
  MOODLE_DB_PASSWORD="$(aws --region "${AWS_REGION}" secretsmanager get-secret-value --secret-id "${MOODLE_SECRET_ID}" --query SecretString --output text)"
fi
if [[ -n "${OSTICKET_SECRET_ID}" ]]; then
  OSTICKET_DB_PASSWORD="$(aws --region "${AWS_REGION}" secretsmanager get-secret-value --secret-id "${OSTICKET_SECRET_ID}" --query SecretString --output text)"
fi

# osTicket uses moodle_admin by default in this stack, so keep it pinned to Moodle password
# unless a different DB user is explicitly provided.
if [[ "${OSTICKET_DB_USER}" == "${MOODLE_DB_USER}" ]]; then
  OSTICKET_DB_PASSWORD="${MOODLE_DB_PASSWORD}"
  OSTICKET_SECRET_ID=""
fi

echo "Updating kubeconfig for ${CLUSTER_NAME} (${AWS_REGION})..."
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
if [[ -z "${TARGET_IMAGE}" && "${SKIP_IMAGE_PUSH}" == "true" ]]; then
  TARGET_IMAGE="$(kubectl get deployment odoo-private -n odoo-private -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
fi
if [[ -z "${TARGET_IMAGE}" && "${SKIP_IMAGE_PUSH}" == "true" ]]; then
  echo "Error: --skip-image-push requires --target-image, or an existing odoo-private deployment image to reuse." >&2
  exit 1
fi
if [[ -z "${TARGET_IMAGE}" ]]; then
  TARGET_IMAGE="${ECR_REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG}"
fi

if [[ "${SKIP_IMAGE_PUSH}" != "true" ]]; then
  echo "Validating source image exists locally: ${SOURCE_IMAGE}"
  docker image inspect "${SOURCE_IMAGE}" >/dev/null

  if ! aws ecr describe-repositories --region "${AWS_REGION}" --repository-names "${ECR_REPO_NAME}" >/dev/null 2>&1; then
    echo "Creating ECR repository ${ECR_REPO_NAME}..."
    aws ecr create-repository --region "${AWS_REGION}" --repository-name "${ECR_REPO_NAME}" >/dev/null
  fi

  echo "Logging into ECR..."
  aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${ECR_REGISTRY}" >/dev/null

  echo "Tagging and pushing image: ${TARGET_IMAGE}"
  docker tag "${SOURCE_IMAGE}" "${TARGET_IMAGE}"
  docker push "${TARGET_IMAGE}"
else
  echo "Skipping image push, using target image reference: ${TARGET_IMAGE}"
fi

if [[ "${SKIP_DEPLOY}" != "true" ]]; then
  DEPLOY_ARGS=(
    --terraform-dir "${TERRAFORM_DIR}"
    --aws-region "${AWS_REGION}"
    --odoo-db-user "${ODOO_DB_USER}"
    --odoo-image "${TARGET_IMAGE}"
  )
  if [[ -n "${ODOO_SECRET_ID}" ]]; then
    DEPLOY_ARGS+=(--odoo-secret-id "${ODOO_SECRET_ID}")
  elif [[ -n "${ODOO_DB_PASSWORD}" ]]; then
    DEPLOY_ARGS+=(--odoo-db-password "${ODOO_DB_PASSWORD}")
  else
    echo "Error: provide --odoo-db-password or --odoo-secret-id for deploy step." >&2
    exit 1
  fi
  if [[ -n "${MOODLE_SECRET_ID}" ]]; then
    DEPLOY_ARGS+=(--moodle-secret-id "${MOODLE_SECRET_ID}")
  elif [[ -n "${MOODLE_DB_PASSWORD}" ]]; then
    DEPLOY_ARGS+=(--moodle-db-password "${MOODLE_DB_PASSWORD}")
  else
    echo "Error: provide --moodle-db-password or --moodle-secret-id for deploy step." >&2
    exit 1
  fi
  if [[ -n "${OSTICKET_SECRET_ID}" ]]; then
    DEPLOY_ARGS+=(--osticket-secret-id "${OSTICKET_SECRET_ID}")
  elif [[ -n "${OSTICKET_DB_PASSWORD}" ]]; then
    DEPLOY_ARGS+=(--osticket-db-password "${OSTICKET_DB_PASSWORD}")
  fi

  if [[ -z "${ODOO_DB_PASSWORD}" ]]; then
    ODOO_DB_PASSWORD="$(kubectl get secret odoo-db -n odoo-private -o jsonpath='{.data.password}' | base64 --decode)"
  fi

  # Required by deploy-k8s-apps.sh as well.
  if [[ -z "${ODOO_DB_PASSWORD}" ]]; then
    echo "Error: resolved Odoo DB password is empty." >&2
    exit 1
  fi

  echo "Deploying manifests with Odoo image ${TARGET_IMAGE}..."
  "${SCRIPT_DIR}/deploy-k8s-apps.sh" --skip-odoo-rollout-wait "${DEPLOY_ARGS[@]}"
else
  if [[ -z "${ODOO_DB_PASSWORD}" ]]; then
    ODOO_DB_PASSWORD="$(kubectl get secret odoo-db -n odoo-private -o jsonpath='{.data.password}' | base64 --decode || true)"
  fi
fi

if [[ "${SKIP_DB_RESTORE}" != "true" || "${SKIP_FILESTORE_SYNC}" != "true" || "${SKIP_MODULE_UPGRADE}" != "true" ]]; then
  echo "Scaling Odoo deployments down during bootstrap..."
  kubectl scale deployment/odoo-private -n odoo-private --replicas=0 >/dev/null || true
  kubectl scale deployment/odoo-public -n odoo-public --replicas=0 >/dev/null || true
fi

if [[ "${SKIP_DB_RESTORE}" != "true" ]]; then
  POD_NAME="odoo-db-restore-$(date +%s)"
  echo "Starting DB restore pod ${POD_NAME}..."
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
  kubectl exec -i -n odoo-private "${POD_NAME}" -- sh -ceu "cat > /tmp/odoo.sql.gz" < "${SQL_DUMP_FILE}"
  kubectl exec -n odoo-private "${POD_NAME}" -- sh -ceu "
psql -h '${ODOO_DB_HOST}' -U '${ODOO_DB_USER}' -d postgres -tAc \"SELECT 1 FROM pg_roles WHERE rolname='odoo17'\" | grep -q 1 || psql -h '${ODOO_DB_HOST}' -U '${ODOO_DB_USER}' -d postgres -c \"CREATE ROLE odoo17\";
psql -h '${ODOO_DB_HOST}' -U '${ODOO_DB_USER}' -d postgres -c \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${ODOO_DB_NAME}' AND pid <> pg_backend_pid();\";
psql -h '${ODOO_DB_HOST}' -U '${ODOO_DB_USER}' -d postgres -c \"DROP DATABASE IF EXISTS ${ODOO_DB_NAME};\";
psql -h '${ODOO_DB_HOST}' -U '${ODOO_DB_USER}' -d postgres -c \"CREATE DATABASE ${ODOO_DB_NAME} OWNER ${ODOO_DB_USER};\";
gunzip -c /tmp/odoo.sql.gz | psql -h '${ODOO_DB_HOST}' -U '${ODOO_DB_USER}' -d '${ODOO_DB_NAME}';
"
  kubectl delete pod "${POD_NAME}" -n odoo-private --ignore-not-found >/dev/null
  echo "DB restore completed."
fi

if [[ "${SKIP_FILESTORE_SYNC}" != "true" ]]; then
  POD_NAME="odoo-filestore-sync-$(date +%s)"
  echo "Starting filestore sync pod ${POD_NAME}..."
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
        claimName: odoo-pvc
EOF
  kubectl wait --for=condition=Ready "pod/${POD_NAME}" -n odoo-private --timeout=180s >/dev/null
  kubectl exec -n odoo-private "${POD_NAME}" -- sh -c "mkdir -p /mnt/odoo-data/filestore && rm -rf /mnt/odoo-data/filestore/${ODOO_DB_NAME}"
  tar -C "${FILESTORE_DIR}" -cf - . | kubectl exec -i -n odoo-private "${POD_NAME}" -- sh -ceu "mkdir -p /mnt/odoo-data/filestore/${ODOO_DB_NAME} && tar -xf - -C /mnt/odoo-data/filestore/${ODOO_DB_NAME}"
  kubectl exec -n odoo-private "${POD_NAME}" -- sh -c "chown -R 101:101 /mnt/odoo-data/filestore/${ODOO_DB_NAME} || true"
  kubectl delete pod "${POD_NAME}" -n odoo-private --ignore-not-found >/dev/null
  echo "Filestore sync completed."
fi

if [[ "${SKIP_MODULE_UPGRADE}" != "true" ]]; then
  JOB_NAME="odoo-module-upgrade-$(date +%s)"
  echo "Running module upgrade job ${JOB_NAME}..."
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
    echo "Module upgrade job failed. Recent logs:"
    kubectl logs "job/${JOB_NAME}" -n odoo-private --tail=200 || true
    exit 1
  fi
  kubectl logs "job/${JOB_NAME}" -n odoo-private --tail=100
  echo "Module upgrade completed."
fi

if [[ "${SKIP_DB_RESTORE}" != "true" || "${SKIP_FILESTORE_SYNC}" != "true" || "${SKIP_MODULE_UPGRADE}" != "true" ]]; then
  echo "Scaling Odoo deployments up..."
  kubectl scale deployment/odoo-private -n odoo-private --replicas=1 >/dev/null || true
  kubectl scale deployment/odoo-public -n odoo-public --replicas=1 >/dev/null || true
  kubectl rollout status deployment/odoo-private -n odoo-private --timeout=300s
  kubectl rollout status deployment/odoo-public -n odoo-public --timeout=300s
fi

echo
echo "Done."
echo "Deployed image: ${TARGET_IMAGE}"
echo "Odoo DB host: ${ODOO_DB_HOST}"
echo "Odoo DB name: ${ODOO_DB_NAME}"
