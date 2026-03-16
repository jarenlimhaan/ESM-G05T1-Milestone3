# ESM Enterprise Platform

Terraform provisions AWS infrastructure (VPC, EKS, RDS, EFS, VPN, ALB, monitoring).  
Kubernetes manifests deploy Moodle and Odoo on EKS.

## Repo Layout

```text
.
|-- terraform/             # AWS infrastructure
|-- k8s/                   # Kubernetes manifests (apps)
|-- scripts/
|   |-- deploy-k8s-apps.ps1 # PowerShell helper deploy script
|   `-- deploy-k8s-apps.sh  # Bash helper deploy script
`-- DEPLOYMENT.md          # Full step-by-step runbook
```

## Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform installed
- kubectl installed
- IAM permissions for EKS, VPC, RDS, EFS, ELB, IAM, CloudWatch, SNS, Backup

## Quick Start

From repo root:

```powershell
# 1) Create AWS infrastructure
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve

# 2) Configure kubectl for EKS
aws eks update-kubeconfig --name esm-enterprise-prod-eks --region ap-southeast-1

# 3) Deploy apps
kubectl apply -k k8s

# 4) Verify
kubectl get pods -n esm
kubectl get svc -n esm -o wide
```

## Access Endpoints

```powershell
kubectl get svc -n esm odoo-public odoo-vpn moodle-public moodle-vpn
```

- `*-public`: internet-facing NLB endpoint
- `*-vpn`: internal NLB endpoint (for VPN/private routing)

## Pod Health Commands

```powershell
kubectl get pods -n esm
kubectl get pods -n esm -w
kubectl get pods -n esm -o wide
kubectl logs -n esm deployment/odoo --tail=100
kubectl logs -n esm deployment/moodle --tail=100
```

## Tear Down

```powershell
# Remove apps
kubectl delete -k k8s

# Destroy AWS infrastructure
terraform -chdir=terraform destroy -auto-approve
```

## Bring It Back Later

```powershell
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve
aws eks update-kubeconfig --name esm-enterprise-prod-eks --region ap-southeast-1
kubectl apply -k k8s
```

For full deployment and troubleshooting flow, use `DEPLOYMENT.md`.

## Helper Script (Bash)

```bash
./scripts/deploy-k8s-apps.sh \
  --odoo-db-password "ChangeMeSecurePassword123!" \
  --moodle-db-password "ChangeMeSecurePassword456!"
```

If you also want the script to run Terraform provisioning first:

```bash
./scripts/deploy-k8s-apps.sh \
  --provision-infra \
  --odoo-db-password "ChangeMeSecurePassword123!" \
  --moodle-db-password "ChangeMeSecurePassword456!"
```
