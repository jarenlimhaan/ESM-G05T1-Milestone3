#!/usr/bin/env bash
# Push the Odoo image to ECR, then restore the PostgreSQL database.
# Run from repo root: ./scripts/push-odoo-to-ecr.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
CLUSTER_NAME="esm-enterprise-prod-eks"

# ECR
PUBLIC_IMAGE="odoo:17"
ECR_REPO="esm/odoo17"
ECR_TAG="17"

# Database
DB_HOST="esm-enterprise-prod-odoo.c9asmcmsm7pz.ap-southeast-1.rds.amazonaws.com"
DB_NAME="odoodb"
DB_USER="odoo_admin"
SQL_DUMP="${REPO_ROOT}/data/odoo17/odoo.sql.gz"

# ── Preflight ──────────────────────────────────────────────────────────────────
[[ -f "${SQL_DUMP}" ]] || { echo "Error: SQL dump not found: ${SQL_DUMP}" >&2; exit 1; }

# ── Phase 1: Push image to ECR ─────────────────────────────────────────────────
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_IMAGE="${ECR_REGISTRY}/${ECR_REPO}:${ECR_TAG}"

echo "==> Creating ECR repo (if missing)..."
aws ecr create-repository --region "${AWS_REGION}" --repository-name "${ECR_REPO}" 2>/dev/null || \
  echo "    Repo already exists, continuing."

echo "==> Logging in to ECR..."
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

echo "==> Pulling public image: ${PUBLIC_IMAGE}..."
docker pull "${PUBLIC_IMAGE}"

echo "==> Tagging as: ${ECR_IMAGE}..."
docker tag "${PUBLIC_IMAGE}" "${ECR_IMAGE}"

echo "==> Pushing to ECR..."
docker push "${ECR_IMAGE}"
echo "    Image pushed: ${ECR_IMAGE}"

# ── Phase 2: Restore PostgreSQL database ──────────────────────────────────────
echo ""
echo "==> Authenticating to EKS cluster: ${CLUSTER_NAME}..."
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null

echo "==> Scaling down Odoo deployments..."
kubectl scale deployment/odoo-private -n odoo-private --replicas=0 2>/dev/null || true
kubectl scale deployment/odoo-public  -n odoo-public  --replicas=0 2>/dev/null || true

POD_NAME="odoo-db-restore-$(date +%s)"
echo "==> Starting restore pod: ${POD_NAME}..."

# PGPASSWORD is injected from the existing odoo-db k8s secret — never in plaintext.
kubectl apply -f - >/dev/null <<EOF
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

echo "==> Waiting for restore pod to be ready..."
kubectl wait --for=condition=Ready "pod/${POD_NAME}" -n odoo-private --timeout=120s >/dev/null

echo "==> Uploading SQL dump to pod..."
kubectl exec -i -n odoo-private "${POD_NAME}" -- sh -ceu "cat > /tmp/odoo.sql.gz" < "${SQL_DUMP}"

echo "==> Restoring database ${DB_NAME}..."
kubectl exec -n odoo-private "${POD_NAME}" -- sh -ceu "
psql -h '${DB_HOST}' -U '${DB_USER}' -d postgres -tAc \
  \"SELECT 1 FROM pg_roles WHERE rolname='odoo17'\" | grep -q 1 || \
  psql -h '${DB_HOST}' -U '${DB_USER}' -d postgres -c \"CREATE ROLE odoo17\";
psql -h '${DB_HOST}' -U '${DB_USER}' -d postgres -c \
  \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${DB_NAME}' AND pid <> pg_backend_pid();\";
psql -h '${DB_HOST}' -U '${DB_USER}' -d postgres -c \"DROP DATABASE IF EXISTS ${DB_NAME};\";
psql -h '${DB_HOST}' -U '${DB_USER}' -d postgres -c \"CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};\";
gunzip -c /tmp/odoo.sql.gz | psql -h '${DB_HOST}' -U '${DB_USER}' -d '${DB_NAME}';
"

echo "==> Cleaning up restore pod..."
kubectl delete pod "${POD_NAME}" -n odoo-private --ignore-not-found >/dev/null

echo "==> Scaling Odoo deployments back up..."
kubectl scale deployment/odoo-private -n odoo-private --replicas=1
kubectl scale deployment/odoo-public  -n odoo-public  --replicas=1

echo ""
echo "Done."
echo "  Image : ${ECR_IMAGE}"
echo "  DB    : ${DB_HOST} / ${DB_NAME}"
