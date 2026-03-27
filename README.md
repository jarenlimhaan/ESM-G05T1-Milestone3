# ESM AWS + Kubernetes (School Project)

This repository provisions AWS infrastructure with Terraform and deploys apps to EKS with Kubernetes manifests.

## Architecture Summary

- Public access:
  - Odoo (public) at root path on public ALB domain.
- Internal (VPN only):
  - Odoo (internal), Moodle, and osTicket at root path on internal private DNS hostnames.
- Infra:
  - VPC, EKS, RDS (Postgres + MySQL), EFS, ALB (public/internal), VPN, WAF, Backup, Monitoring.

## Repo Layout

- `terraform/` -> infrastructure provisioning
- `k8s/` -> Kubernetes manifests (template placeholders)
- `scripts/` -> deploy/teardown/VPN helper scripts

## Local Docker (Odoo 17)

Use this when you want to run Odoo locally with the provided SQL dump and filestore.

1. Copy env file:

```bash
cp .env.example .env
```

2. Prepare required external addons:

```powershell
./scripts/prepare-odoo-addons.ps1
```

3. Start containers:

```bash
docker compose up -d
```

4. Follow logs:

```bash
docker compose logs -f db odoo
```

5. Open Odoo:

```text
http://localhost:8069
```

Important:
- SQL import (`odoo17/odoo.sql.gz`) only runs on first DB initialization.
- To re-import from scratch, remove the DB volume first:

```bash
docker compose down -v
docker compose up -d
```

## Prerequisites

Install and configure:

1. `aws` CLI (authenticated to your AWS account)
2. `terraform`
3. `kubectl`
4. `bash` (Git Bash/WSL/macOS/Linux)
5. `jq`, `perl` (required by scripts)
6. `docker` / Docker Desktop (required for Odoo image push in rebuild flow)

Validate quickly:

```bash
aws sts get-caller-identity
terraform -version
kubectl version --client
```

## Quick Start (From Scratch)

### 1. (Optional) Tear Down Existing Stack First

```bash
./scripts/destroy-everything.sh
```

### 2. Rebuild Full Stack (Recommended)

This is the default workflow now. It will:
- destroy old stack (unless you pass `--skip-destroy`),
- provision infra,
- build/push your local Odoo image to ECR,
- deploy Kubernetes manifests,
- run bootstrap tasks (Odoo DB restore + filestore sync + module upgrade),
- auto-repair Moodle DB if install is partial (`mdl_config.version` missing).

```bash
./scripts/rebuild-from-scratch.sh
```

If Docker is unavailable and you already have a valid image in ECR:

```bash
./scripts/deploy-odoo-image-to-eks.sh \
  --skip-image-push \
  --target-image "<your-ecr-image:tag>" \
  --provision-infra
```

### 3. Deploy Infra + Kubernetes Apps (Direct Script)

Use direct DB passwords:

```bash
./scripts/deploy-k8s-apps.sh \
  --provision-infra \
  --odoo-db-password "OdooPassword" \
  --moodle-db-password "MoodlePassword" \
  --osticket-db-password "MoodlePassword"
```

Or use AWS Secrets Manager IDs:

```bash
./scripts/deploy-k8s-apps.sh \
  --provision-infra \
  --odoo-secret-id "esm/prod/odoo-db-password" \
  --moodle-secret-id "esm/prod/moodle-db-password" \
  --osticket-secret-id "esm/prod/osticket-db-password"
```

### 4. Get Endpoints

```bash
terraform -chdir=terraform output application_access_urls
```

### 5. Generate VPN Profile (Internal Access)

```bash
./scripts/generate-vpn-profile.sh --output "$HOME/Downloads/esm-vpn-config-fixed.ovpn"
```

Import the generated `.ovpn` into AWS VPN Client, connect, then access internal hosts.

## Day-2 Operations

### Redeploy Kubernetes manifests after changes

```bash
./scripts/deploy-k8s-apps.sh \
  --odoo-db-password "OdooPassword" \
  --moodle-db-password "MoodlePassword" \
  --osticket-db-password "MoodlePassword"
```

### Sync K8s secrets from AWS Secrets Manager

```bash
./scripts/sync-k8s-secrets-from-aws.sh \
  --region ap-southeast-1 \
  --odoo-secret-id esm/prod/odoo-db-password \
  --moodle-secret-id esm/prod/moodle-db-password \
  --osticket-secret-id esm/prod/osticket-db-password \
  --osticket-install-secret "put-a-long-random-string-here-please-change-me" \
  --osticket-admin-password "ChangeThisAdminPassword123!"
```

## Teardown

Full cleanup:

```bash
./scripts/destroy-everything.sh
```

Infra-only cleanup:

```bash
./scripts/destroy-everything.sh --skip-k8s
```

K8s-only cleanup:

```bash
./scripts/destroy-everything.sh --skip-terraform
```

## Notes

- Use `scripts/deploy-k8s-apps.sh` (not raw `kubectl apply -k k8s`) because manifests contain placeholders and must be rendered first.
- osTicket K8s rendering now follows the same env contract as `docker-compose-osTicket.yaml` (image, install/admin settings, DB settings).
- `scripts/deploy-k8s-apps.sh` reads `.env` defaults for osTicket keys (`OSTICKET_IMAGE`, `INSTALL_*`, `ADMIN_*`, `CRON_INTERVAL`) unless overridden via CLI flags.
- `scripts/rebuild-from-scratch.sh` calls `destroy-everything.sh` then `deploy-odoo-image-to-eks.sh --provision-infra`.
- If `OSTICKET_DB_USER` is `moodle_admin`, deploy scripts hard-enforce osTicket to use the Moodle DB password to prevent secret drift.
- If you destroy/recreate often, endpoints and VPN configuration can change. Re-generate VPN profile after each fresh create.
- For school demo cost control: destroy stack immediately when not in use.
