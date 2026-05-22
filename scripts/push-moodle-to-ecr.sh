#!/usr/bin/env bash
# Push the Moodle image to ECR, then restore the MySQL database.
# Run from repo root: ./scripts/push-moodle-to-ecr.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
CLUSTER_NAME="esm-enterprise-prod-eks"

# ECR
PUBLIC_IMAGE="ellakcy/moodle:mysql_maria_apache_latest"
ECR_REPO="esm/moodle"
ECR_TAG="mysql_maria_apache_latest"

# Database
DB_HOST="esm-enterprise-prod-moodle.c9asmcmsm7pz.ap-southeast-1.rds.amazonaws.com"
DB_NAME="moodledb"
DB_USER="moodle_admin"
# moodle-course-backup.mbz is a gzip SQL dump despite the extension
SQL_DUMP="${REPO_ROOT}/data/moodle-course-backup.mbz"

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

# ── Phase 2: Restore MySQL database ───────────────────────────────────────────
echo ""
echo "==> Authenticating to EKS cluster: ${CLUSTER_NAME}..."
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null

echo "==> Scaling down Moodle deployment..."
kubectl scale deployment/moodle -n moodle-private --replicas=0 2>/dev/null || true

POD_NAME="moodle-db-restore-$(date +%s)"
echo "==> Starting restore pod: ${POD_NAME}..."

# MYSQL_PWD is injected from the existing moodle-db k8s secret — never in plaintext.
kubectl apply -f - >/dev/null <<EOF
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

echo "==> Waiting for restore pod to be ready..."
kubectl wait --for=condition=Ready "pod/${POD_NAME}" -n moodle-private --timeout=120s >/dev/null

echo "==> Uploading SQL dump to pod..."
kubectl exec -i -n moodle-private "${POD_NAME}" -- sh -ceu "cat > /tmp/moodle.sql.gz" < "${SQL_DUMP}"

echo "==> Restoring database ${DB_NAME}..."
kubectl exec -n moodle-private "${POD_NAME}" -- sh -ceu "
mysql -h '${DB_HOST}' -u '${DB_USER}' -e \"DROP DATABASE IF EXISTS ${DB_NAME};\";
mysql -h '${DB_HOST}' -u '${DB_USER}' -e \"CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\";
gunzip -c /tmp/moodle.sql.gz | mysql -h '${DB_HOST}' -u '${DB_USER}' '${DB_NAME}';
"

echo "==> Cleaning up restore pod..."
kubectl delete pod "${POD_NAME}" -n moodle-private --ignore-not-found >/dev/null

echo "==> Scaling Moodle deployment back up..."
kubectl scale deployment/moodle -n moodle-private --replicas=1

echo ""
echo "Done."
echo "  Image : ${ECR_IMAGE}"
echo "  DB    : ${DB_HOST} / ${DB_NAME}"
