#!/usr/bin/env bash
# Push the public osTicket image to ECR and redeploy.
# Run from repo root: ./scripts/push-osticket-to-ecr.sh
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
PUBLIC_IMAGE="devinsolutions/osticket:1.17.5"
ECR_REPO="esm/osticket"
ECR_TAG="1.17.5"

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

echo ""
echo "Image pushed: ${ECR_IMAGE}"
echo ""
echo "==> Deleting existing osticket K8s deployment (if any)..."
kubectl delete deployment osticket -n osticket-private --ignore-not-found || true

echo ""
echo "==> Running deploy with the ECR image (skipping DB restores — run deploy-odoo-image-to-eks.sh separately for full restore)..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/deploy-odoo-image-to-eks.sh" \
  --skip-image-push \
  --target-image "$(kubectl get deployment odoo-private -n odoo-private -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo 'odoo:17')" \
  --osticket-image "${ECR_IMAGE}" \
  --skip-db-restore \
  --skip-osticket-db-restore \
  --skip-moodle-db-restore \
  --skip-filestore-sync \
  --skip-module-upgrade

echo ""
echo "Done. osTicket redeployed with image: ${ECR_IMAGE}"
