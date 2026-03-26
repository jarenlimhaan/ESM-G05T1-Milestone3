# Deployment Runbook

This document is the step-by-step runbook for creating and destroying the full stack safely.

## 1) Initial Setup

1. Configure AWS credentials/profile.
2. Ensure region is correct (`ap-southeast-1` unless you changed Terraform vars).
3. Confirm tooling:

```bash
aws sts get-caller-identity
terraform -version
kubectl version --client
```

## 2) Fresh Deployment

### Recommended: one-command rebuild

```bash
./scripts/rebuild-from-scratch.sh
```

This runs:
- `destroy-everything.sh` (unless `--skip-destroy`),
- infra provisioning,
- Odoo image push to ECR,
- k8s deploy,
- Odoo bootstrap (DB restore/filestore/module upgrade),
- Moodle DB self-heal check.

### Option A: Deploy with inline passwords

```bash
./scripts/deploy-k8s-apps.sh \
  --provision-infra \
  --odoo-db-password "OdooPassword" \
  --moodle-db-password "MoodlePassword" \
  --osticket-db-password "MoodlePassword"
```

### Option B: Deploy with AWS Secrets Manager

```bash
./scripts/deploy-k8s-apps.sh \
  --provision-infra \
  --odoo-secret-id "esm/prod/odoo-db-password" \
  --moodle-secret-id "esm/prod/moodle-db-password" \
  --osticket-secret-id "esm/prod/osticket-db-password"
```

## 3) Post-Deploy Verification

### 3.1 Cluster health

```bash
kubectl get nodes
kubectl get pods -A
kubectl get pods -n odoo-public
kubectl get pods -n odoo-private
kubectl get pods -n moodle-private
kubectl get pods -n osticket-private
```

### 3.2 Endpoints output

```bash
terraform -chdir=terraform output application_access_urls
```

### 3.3 VPN for internal apps

```bash
./scripts/generate-vpn-profile.sh --output "$HOME/Downloads/esm-vpn-config-fixed.ovpn"
```

Import profile into AWS VPN Client and connect.

### 3.4 Connectivity checks

```bash
curl -I "http://$(terraform -chdir=terraform output -raw public_alb_dns_name)/"
```

Internal examples (after VPN connect):

```bash
curl -I "http://odoo.internal.esm.local/"
curl -I "http://moodle.internal.esm.local/"
curl -I "http://osticket.internal.esm.local/"
```

## 4) Common Troubleshooting

### Placeholder values appear in live deployment

Cause: raw `kubectl apply -k k8s` was used.
Fix: re-run `scripts/deploy-k8s-apps.sh` so placeholders are rendered.

### Moodle shows "Config table does not contain the version"

Cause: partial/failed Moodle install left DB incomplete.
Fix: `deploy-k8s-apps.sh` now auto-detects this and recreates `moodledb` then restarts Moodle.

### VPN connects but internal domain is unreachable

1. Re-generate profile after recreate.
2. Reconnect VPN.
3. Verify private DNS resolves:

```bash
nslookup odoo.internal.esm.local
```

### osTicket/Moodle/Odoo pods not ready

```bash
kubectl describe pod -n <namespace> <pod-name>
kubectl logs -n <namespace> <pod-name> --tail=200
```

## 5) Safe Teardown (Cost Control)

Recommended full cleanup:

```bash
./scripts/destroy-everything.sh
```

What it does:
- deletes Kubernetes resources first (to reduce ALB/NLB dependency issues)
- optionally removes known RDS final snapshots
- runs `terraform destroy -auto-approve`

Optional flags:

```bash
./scripts/destroy-everything.sh --skip-k8s
./scripts/destroy-everything.sh --skip-terraform
./scripts/destroy-everything.sh --skip-snapshot-cleanup
```

## 6) Rebuild Later

When you want to run demo again:

```bash
./scripts/rebuild-from-scratch.sh \
  --odoo-db-password "OdooPassword" \
  --moodle-db-password "MoodlePassword" \
  --osticket-db-password "MoodlePassword"
```

This wrapper tears down first, then deploys infra + apps.

If you use this wrapper, Docker must be available for Odoo image push.
