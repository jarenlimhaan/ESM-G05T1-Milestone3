# ESM AWS + Kubernetes

This repository provisions the ESM AWS environment through a three-level landing-zone Terraform layout, then deploys the Kubernetes workloads and bootstraps application data.

## Architecture Summary

- Public access: Odoo public site through the public ALB.
- Internal access: Odoo internal, Moodle, and osTicket through VPN/private DNS.
- Infrastructure: VPC, EKS, RDS, EFS, ALBs, VPN, WAF, AWS Backup, CloudTrail, and CloudWatch monitoring.

## Repo Layout

- `terraform/lz0-storage/` - Level 0 foundation/storage/audit resources.
- `terraform/lz1-network/` - Level 1 VPC, subnets, security groups, and VPN.
- `terraform/lz2-orchestration/` - Level 2 EKS, RDS, EFS, ALB, DNS, WAF, monitoring, and secrets.
- `terraform/modules/` - Shared Terraform modules used by the landing zones.
- `k8s/` - Source Kubernetes manifests with placeholders.
- `k8s-rendered/` - Rendered manifests for ArgoCD.
- `argocd/` - ArgoCD Application definition.
- `scripts/` - Landing-zone apply/destroy, Kubernetes render/apply, bootstrap, VPN, and ArgoCD helpers.

## Prerequisites

Install and configure:

1. `aws` CLI authenticated to the target AWS account.
2. `terraform`.
3. `kubectl`.
4. `bash` such as Git Bash, WSL, macOS, or Linux shell.
5. `jq` and `perl`.
6. Docker only if you need to build/push a new Odoo image.

Validate:

```bash
aws sts get-caller-identity
terraform -version
kubectl version --client
```

## One-Shot Local Deployment

The current local deployment entry point is:

```bash
./scripts/apply-landing-zones.sh \
  --aws-region ap-southeast-1 \
  --odoo-db-password "$ODOO_DB_PASSWORD" \
  --moodle-db-password "$MOODLE_DB_PASSWORD" \
  --osticket-db-password "$OSTICKET_DB_PASSWORD" \
  --osticket-install-secret "$INSTALL_SECRET" \
  --osticket-admin-password "$ADMIN_PASSWORD"
```

This runs, in order:

1. Terraform Level 0: storage/foundation/audit.
2. Terraform Level 1: network and VPN.
3. Terraform Level 2: platform and application infrastructure.
4. Kubernetes manifest render/apply through `deploy-k8s-apps.sh`.
5. Bootstrap through `deploy-odoo-image-to-eks.sh` using the existing ECR image.

Use these flags when you need a partial run:

```bash
./scripts/apply-landing-zones.sh --skip-k8s-apps ...
./scripts/apply-landing-zones.sh --skip-bootstrap ...
```

## Teardown

Use the landing-zone destroy wrapper:

```bash
./scripts/destroy-landing-zones.sh --aws-region ap-southeast-1
```

This cleans Kubernetes resources first, then destroys Level 2, Level 1, and Level 0 in reverse dependency order.

## Outputs

After apply:

```bash
terraform -chdir=terraform/lz2-orchestration output application_access_urls
terraform -chdir=terraform/lz2-orchestration output -raw public_alb_dns_name
```

## VPN Profile

Generate a fresh VPN profile after every full rebuild because VPN endpoint/cert values can change:

```bash
./scripts/generate-vpn-profile.sh --output "$HOME/Downloads/esm-vpn-config-fixed.ovpn"
```

Import the `.ovpn` into AWS VPN Client, connect, then test internal hosts:

```bash
curl -I http://odoo.internal.esm.local/
curl -I http://moodle.internal.esm.local/
curl -I http://osticket.internal.esm.local/
```

## ArgoCD Flow

ArgoCD watches `k8s-rendered/`, not `k8s/`, because the raw `k8s/` manifests contain placeholders for AWS outputs such as ALB groups, RDS endpoints, EFS IDs, image references, and secrets.

Typical ArgoCD preparation:

```bash
./scripts/install-argocd.sh --aws-region ap-southeast-1
./scripts/render-k8s-for-argocd.sh --aws-region ap-southeast-1
kubectl apply -f argocd/application.yaml
```

Commit and push `k8s-rendered/` changes for ArgoCD to reconcile from Git.

## Notes

- Do not apply raw `k8s/` directly with `kubectl apply -k k8s`; use the render/apply scripts.
- `.env` is for local convenience only. Do not commit secrets.
- The Terraform backend S3 bucket is intentionally kept outside normal teardown.
- Destroy demo stacks when not in use to control AWS cost.
