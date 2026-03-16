# Deployment Runbook

This guide is the full command reference to deploy, test, tear down, and redeploy the ESM stack.

## 1) Pre-Flight Checks

From repo root (`c:\Users\jaren\Documents\repos\esm`):

```powershell
aws --version
terraform -version
kubectl version --client
```

Check AWS identity:

```powershell
aws sts get-caller-identity
```

## 2) Deploy Infrastructure (Terraform)

```powershell
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out tfplan
terraform -chdir=terraform apply -auto-approve tfplan
```

Useful outputs:

```powershell
terraform -chdir=terraform output
terraform -chdir=terraform output -json
terraform -chdir=terraform output -raw eks_cluster_name
terraform -chdir=terraform output -raw aws_region
```

## 3) Connect kubectl to EKS

```powershell
aws eks update-kubeconfig --name esm-enterprise-prod-eks --region ap-southeast-1
kubectl config current-context
kubectl get nodes
```

## 4) Deploy Kubernetes Apps

```powershell
kubectl apply -k k8s
```

Or use the Bash helper:

```bash
./scripts/deploy-k8s-apps.sh \
  --odoo-db-password "ChangeMeSecurePassword123!" \
  --moodle-db-password "ChangeMeSecurePassword456!"
```

Wait for readiness:

```powershell
kubectl rollout status deployment/odoo -n esm --timeout=300s
kubectl rollout status deployment/moodle -n esm --timeout=300s
```

## 5) Verify Health

Pods and services:

```powershell
kubectl get pods -n esm
kubectl get svc -n esm -o wide
kubectl get endpoints -n esm
```

App logs:

```powershell
kubectl logs -n esm deployment/odoo --tail=100
kubectl logs -n esm deployment/moodle --tail=100
```

## 6) Find Access Endpoints

```powershell
kubectl get svc -n esm odoo-public odoo-vpn moodle-public moodle-vpn
```

Expected:

- `odoo-public`: public endpoint
- `odoo-vpn`: private/internal endpoint
- `moodle-public`: public endpoint
- `moodle-vpn`: private/internal endpoint

Quick HTTP checks:

```powershell
$odooPub = (kubectl get svc odoo-public -n esm -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
$moodlePub = (kubectl get svc moodle-public -n esm -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
curl.exe -s -o NUL -w "%{http_code}`n" http://$odooPub/web/login
curl.exe -s -o NUL -w "%{http_code}`n" http://$moodlePub/login/index.php
```

## 7) Runtime Operations

Watch pods:

```powershell
kubectl get pods -n esm -w
```

Restart app rollout:

```powershell
kubectl rollout restart deployment/odoo -n esm
kubectl rollout restart deployment/moodle -n esm
```

## 8) Teardown

Delete k8s apps first:

```powershell
kubectl delete -k k8s
```

Destroy AWS infra:

```powershell
terraform -chdir=terraform destroy -auto-approve
```

## 9) Redeploy Later

```powershell
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve
aws eks update-kubeconfig --name esm-enterprise-prod-eks --region ap-southeast-1
kubectl apply -k k8s
kubectl get pods -n esm
kubectl get svc -n esm -o wide
```

## 10) Troubleshooting

`kubectl` cannot connect:

```powershell
aws eks update-kubeconfig --name esm-enterprise-prod-eks --region ap-southeast-1
kubectl config current-context
kubectl get nodes
```

Pods are CrashLoopBackOff:

```powershell
kubectl describe pod <pod-name> -n esm
kubectl logs <pod-name> -n esm --previous
```

Services have no external hostname yet:

```powershell
kubectl get svc -n esm -w
```

Odoo UI asset errors (500):

```powershell
kubectl logs -n esm deployment/odoo --tail=200
kubectl rollout restart deployment/odoo -n esm
```

Moodle shows installer page:

- App is reachable but initial app setup is incomplete.
- Continue Moodle web installer flow (`/install.php`) or provide bootstrap automation later.
