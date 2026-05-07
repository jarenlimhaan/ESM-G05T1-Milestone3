# Deployment Runbook

This runbook uses the landing-zone deployment flow. The old single Terraform root and rebuild wrapper flow has been removed.

## 1. Initial Setup

Configure AWS credentials/profile and verify required tools:

```bash
aws sts get-caller-identity
terraform -version
kubectl version --client
```

Default region is `ap-southeast-1`.

## 2. Fresh Deployment

Run the full landing-zone apply:

```bash
./scripts/apply-landing-zones.sh \
  --aws-region ap-southeast-1 \
  --odoo-db-password "$ODOO_DB_PASSWORD" \
  --moodle-db-password "$MOODLE_DB_PASSWORD" \
  --osticket-db-password "$OSTICKET_DB_PASSWORD" \
  --osticket-install-secret "$INSTALL_SECRET" \
  --osticket-admin-password "$ADMIN_PASSWORD"
```

The script performs:

1. `terraform apply` in `terraform/lz0-storage`.
2. `terraform apply` in `terraform/lz1-network`.
3. `terraform apply` in `terraform/lz2-orchestration`.
4. Kubernetes manifest render/apply.
5. Application bootstrap from existing image references/ECR.

## 3. Post-Deploy Verification

Cluster and pods:

```bash
kubectl get nodes
kubectl get pods -A
kubectl get pods -n odoo-public
kubectl get pods -n odoo-private
kubectl get pods -n moodle-private
kubectl get pods -n osticket-private
```

Application endpoints:

```bash
terraform -chdir=terraform/lz2-orchestration output application_access_urls
curl -I "http://$(terraform -chdir=terraform/lz2-orchestration output -raw public_alb_dns_name)/"
```

VPN/internal access:

```bash
./scripts/generate-vpn-profile.sh --output "$HOME/Downloads/esm-vpn-config-fixed.ovpn"
```

After connecting VPN:

```bash
curl -I http://odoo.internal.esm.local/
curl -I http://moodle.internal.esm.local/
curl -I http://osticket.internal.esm.local/
```

## 4. ArgoCD

Install ArgoCD and apply the Application when the EKS cluster exists:

```bash
./scripts/install-argocd.sh --aws-region ap-southeast-1
./scripts/render-k8s-for-argocd.sh --aws-region ap-southeast-1
kubectl apply -f argocd/application.yaml
kubectl get applications.argoproj.io -n argocd
```

ArgoCD watches `k8s-rendered/`, so regenerate and commit that directory after infrastructure output changes.

## 5. Troubleshooting

Placeholder values appear in live deployment:

```bash
./scripts/deploy-k8s-apps.sh --terraform-dir terraform/lz2-orchestration --aws-region ap-southeast-1
```

Pod not ready:

```bash
kubectl describe pod -n <namespace> <pod-name>
kubectl logs -n <namespace> <pod-name> --tail=200
```

Public Odoo health:

```bash
curl -I "http://$(terraform -chdir=terraform/lz2-orchestration output -raw public_alb_dns_name)/"
```

## 6. Teardown

```bash
./scripts/destroy-landing-zones.sh --aws-region ap-southeast-1
```

This removes Kubernetes resources first, then destroys `lz2`, `lz1`, and `lz0`.
