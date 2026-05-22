# ESM AWS + Kubernetes

This repository provisions the ESM production environment on AWS through a three-level Terraform landing zone, then deploys three enterprise applications — Odoo (ERP), Moodle (LMS), and osTicket (helpdesk) — onto EKS using Helm 3 and ArgoCD.

## Architecture Overview

| Layer | Technology | What it does |
|---|---|---|
| Infrastructure | Terraform (3-level landing zone) | VPC, EKS, RDS, EFS, ALB, VPN, WAF, Backup, CloudTrail |
| Secrets | AWS Secrets Manager + IRSA + Secrets Store CSI | Zero-hardcoded-credentials secret injection |
| Application packaging | Helm 3 | Parameterised charts for Odoo, Moodle, osTicket |
| Persistent storage | AWS EFS + Access Points | Per-app POSIX-isolated volumes |
| GitOps | ArgoCD + App of Apps | Automated deploy and rollback from Git |
| CI guardrails | GitHub Actions, kube-linter, Snyk | Lint, validate, and security-scan on every PR |

### Traffic flow

```
Internet
  │
  └─ Public ALB (WAF-protected)
       └─ Odoo Public  (odoo-public namespace)

VPN clients
  │
  └─ Internal ALB (private subnets)
       ├─ Odoo Private   (odoo-private namespace)   → internal.esm.local/odoo
       ├─ Moodle         (moodle-private namespace)  → internal.esm.local/moodle
       └─ osTicket       (osticket-private namespace)→ internal.esm.local/osticket
```

---

## Terraform Landing Zone and State Management

The infrastructure is split into three ordered landing zones that each own a distinct concern. Every zone stores its state remotely in S3 and uses DynamoDB for locking so concurrent applies are blocked and state is never lost.

```
S3 bucket : esm-enterprise-prod-tf-state-jar
DynamoDB  : esm-enterprise-prod-tf-lock

prod/lz0-storage.tfstate      ← Level 0
prod/lz1-network.tfstate       ← Level 1
prod/lz2-orchestration.tfstate ← Level 2
```

### Level 0 — Storage and audit (`terraform/lz0-storage/`)

Provisions the foundation resources that everything else depends on:

- **S3 state bucket** and **DynamoDB lock table** for Terraform remote state
- **CloudTrail** trail with log-file integrity validation — every AWS API call is captured and auditable before any workload is running

### Level 1 — Network (`terraform/lz1-network/`)

Provisions the network boundary:

- **VPC** `10.0.0.0/16` across two AZs (`ap-southeast-1a/b`)
- Subnet tiers: public (`10.0.1-2.0/24`), private-app (`10.0.10-11.0/24`), private-DB (`10.0.20-21.0/24`)
- **NAT** for outbound internet from private subnets
- **AWS Client VPN** (certificate-based) so team members can reach internal services without opening public ports
- Security groups for EKS, RDS, EFS, both ALBs, and the VPN endpoint

### Level 2 — Orchestration (`terraform/lz2-orchestration/`)

Provisions all application infrastructure using Terraform modules under `terraform/modules/`:

| Module | Resource |
|---|---|
| `eks/` | EKS 1.30 cluster, managed node group (t3.medium ×2–5), OIDC provider |
| `rds/` | PostgreSQL 15 (Odoo), MySQL 8 (Moodle + osTicket shared) — private subnets only |
| `efs/` | EFS file system, mount targets, four Access Points (one per app instance) |
| `alb/` | Public ALB (WAF-attached), internal ALB, target groups, host-based routing |
| `dns/` | Private Route 53 zone `internal.esm.local`, A-records to internal ALB |
| `waf/` | Rate-limit rule (2 000 req / 5 min / IP) on the public ALB |
| `backup/` | AWS Backup vault, daily 3 AM UTC plan, 14-day retention for RDS + EFS |
| `monitoring/` | CloudWatch alarms for RDS CPU, EFS throughput, ALB 5xx rate, pod restarts, $50 monthly budget |
| `cloudtrail/` | (inherited from LZ0) |

Clean module boundaries meant each team member could own a slice of the infrastructure without merge conflicts bleeding across concerns.

### Applying the full stack

```bash
./scripts/apply-landing-zones.sh \
  --aws-region ap-southeast-1 \
  --odoo-db-password      "$ODOO_DB_PASSWORD" \
  --moodle-db-password    "$MOODLE_DB_PASSWORD" \
  --osticket-db-password  "$OSTICKET_DB_PASSWORD" \
  --osticket-install-secret "$INSTALL_SECRET" \
  --osticket-admin-password "$ADMIN_PASSWORD"
```

Partial runs are supported:

```bash
./scripts/apply-landing-zones.sh --skip-bootstrap ...
```

### Teardown

```bash
./scripts/destroy-landing-zones.sh --aws-region ap-southeast-1
```

Kubernetes resources are cleaned first, then Level 2, 1, 0 in reverse dependency order. The S3 state bucket is intentionally excluded from teardown.

---

## Helm and Persistent Storage

All workloads are packaged as Helm 3 charts under `helm/`. Each chart is fully parameterised so the same chart can deploy a private or public instance by overriding a single `instance` value.

```
helm/
├── argocd-apps/   # App-of-Apps parent chart
├── odoo/          # Deploys odoo-private and odoo-public
├── moodle/
└── osticket/
```

Production values live in `prd-*.yaml` override files alongside each chart (e.g. `helm/odoo/prd-odoo-private.yaml`). These files are populated by Terraform outputs — RDS endpoints, EFS IDs, access point IDs, IRSA role ARNs, and ECR image URIs — so no secret or environment-specific value ever needs to be edited by hand.

### EFS Access Points and POSIX isolation

Every application gets a dedicated EFS Access Point that enforces both a root path and a POSIX identity. This was one of the more careful parts of the storage setup: without correct UID/GID enforcement, Odoo and Moodle would fail to write their data directories on startup.

| Application | EFS path | UID / GID | Notes |
|---|---|---|---|
| Odoo private | `/odoo` | 1000 / 1000 | Odoo container runs as uid 1000 |
| Odoo public | `/odoo-public` | 1000 / 1000 | Isolated from private instance |
| Moodle | `/moodle` | 33 / 33 | www-data; stores moodledata |
| osTicket | `/osticket` | 33 / 33 | www-data; stores uploaded attachments |

Each PersistentVolume uses the `efs.csi.aws.com` CSI driver with a `volumeHandle` of `{efsId}::{accessPointId}`. The access point enforces the path and POSIX ownership at the NFS layer, so the pod cannot write outside its designated directory regardless of what the container tries.

```yaml
# helm/odoo/templates/pvc.yaml (excerpt)
spec:
  csi:
    driver: secrets-store.csi.k8s.io   # secrets volume
    ...
---
  csi:
    driver: efs.csi.aws.com             # data volume
    volumeAttributes:
      volumeHandle: "{{ .Values.persistence.efsId }}::{{ .Values.persistence.accessPointId }}"
```

---

## SecretProviderClass and IRSA

No credentials are hardcoded anywhere in the repository. Secrets flow from AWS Secrets Manager into pods via two cooperating mechanisms: IRSA gives each pod's service account the precise IAM permissions it needs, and the Secrets Store CSI Driver uses those permissions to mount secrets into the pod at startup.

### How IRSA is wired up

Terraform provisions an IAM role for each application in `terraform/lz2-orchestration/main.tf`. The role's trust policy binds it to a specific Kubernetes service account via the EKS OIDC provider:

```hcl
# Odoo Private — trust policy (simplified)
condition {
  test     = "StringEquals"
  variable = "${local.oidc_issuer}:sub"
  values   = ["system:serviceaccount:odoo-private:odoo-private"]
}
condition {
  test     = "StringEquals"
  variable = "${local.oidc_issuer}:aud"
  values   = ["sts.amazonaws.com"]
}
```

The `:aud` condition ensures the projected token is for AWS STS, not the Kubernetes API server. The `:sub` condition scopes the role to one service account in one namespace — no other pod can assume it.

The Helm chart annotates the ServiceAccount with the role ARN:

```yaml
# helm/odoo/templates/serviceaccount.yaml
annotations:
  eks.amazonaws.com/role-arn: {{ .Values.serviceAccount.roleArn }}
```

### What each role can access

| Application | IAM role | Secrets |
|---|---|---|
| odoo-private | `...-odoo-private-irsa` | `esm/prod/odoo-db-password` |
| odoo-public | `...-odoo-public-irsa` | `esm/prod/odoo-db-password` |
| moodle | `...-moodle-irsa` | `esm/prod/moodle-db-password`, `esm/prod/moodle-admin-password` |
| osticket | `...-osticket-irsa` | `esm/prod/moodle-db-password` (shared DB), `esm/prod/osticket-install-secret`, `esm/prod/osticket-admin-password` |

Each policy allows only `secretsmanager:GetSecretValue` and `secretsmanager:DescribeSecret` on the listed ARNs — nothing broader.

### SecretProviderClass — mounting secrets into pods

Each Helm chart ships a `SecretProviderClass` that tells the AWS Secrets Store CSI Driver which secrets to fetch and how to expose them:

```yaml
# helm/moodle/templates/secretproviderclass.yaml (excerpt)
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: "esm/prod/moodle-db-password"
        objectType: secretsmanager
        objectAlias: moodle-db-pw
      - objectName: "esm/prod/moodle-admin-password"
        objectType: secretsmanager
        objectAlias: moodle-admin-pw
  secretObjects:
    - secretName: moodle-db
      type: Opaque
      data:
        - objectName: moodle-db-pw
          key: password
        - objectName: moodle-admin-pw
          key: admin_password
```

At pod startup the kubelet calls the CSI driver, which uses the IRSA-provided credentials to call `GetSecretValue`, writes the value as a volume mount, and syncs it into a Kubernetes Secret object (`syncSecret.enabled: true`). The container then reads credentials from that Secret via `secretKeyRef` — standard Kubernetes env var injection. The pod itself never makes an AWS API call; the kubelet handles it. Every `GetSecretValue` call is logged in CloudTrail automatically.

Secret rotation is enabled (`enableSecretRotation: true`, poll interval 2 minutes), so a secret rotated in Secrets Manager is reflected in the pod volume without a redeploy.

### System components (installed by ArgoCD)

The CSI driver and AWS provider are installed as system apps by ArgoCD before workloads come up (syncWave `-2`):

- `secrets-store-csi-driver` v1.4.4 — the generic CSI engine
- `secrets-store-csi-driver-provider-aws` v0.3.9 — the AWS plugin that calls Secrets Manager

---

## CI/CD Pipeline

### GitHub Actions — guardrails on every PR

| Workflow | Trigger | What it checks |
|---|---|---|
| `terraform.yml` | PR → plan, push to main → apply | `fmt`, `validate`, `plan` (comments output on PR), `apply` on merge |
| `k8s-lint.yml` | PR touching `helm/**` | `helm lint` for all four charts + kube-linter on rendered manifests |
| `k8s-validate.yml` | PR touching `helm/**` | `helm template` → kubeconform schema validation, HPA `minReplicas ≥ 1` check |
| `security-and-deploy.yml` | PR + push to main | Checkov IaC scan, Snyk IaC scan (high threshold), deploy script on merge |

#### kube-linter as a CI guardrail

`k8s-lint.yml` renders each Helm chart to a temporary directory and runs kube-linter against the output on every pull request. This catches configuration drift — missing resource limits, privileged containers, missing readiness probes — before anything reaches the cluster.

```yaml
# .github/workflows/k8s-lint.yml (excerpt)
- name: Render Helm charts
  run: |
    helm template odoo-private helm/odoo \
      --values helm/odoo/values.yaml \
      --values helm/odoo/prd-odoo-private.yaml \
      > /tmp/rendered/odoo-private.yaml
    ...
- name: Run kube-linter
  run: kube-linter lint /tmp/rendered --config .kube-linter.yaml
```

### ArgoCD — GitOps deployments and rollbacks

ArgoCD uses the **App of Apps** pattern. A single parent Application (`argocd/bootstrap.yaml`) points at `helm/argocd-apps/`. That chart renders one Application CRD per workload, so the entire cluster state is declared in Git.

```
argocd-apps (parent)
├── system-apps (syncWave -2)
│   ├── metrics-server
│   ├── cluster-autoscaler
│   ├── secrets-store-csi-driver
│   └── secrets-store-csi-driver-provider-aws
└── workload-apps (syncWave -1)
    ├── odoo-private
    ├── odoo-public
    ├── moodle
    └── osticket
```

System apps are installed before workloads via sync waves, ensuring the CSI driver is ready before any pod that needs secrets is scheduled.

`syncPolicy` is set to `automated` with both `prune: true` and `selfHeal: true`:
- **prune** removes resources that are no longer in Git
- **selfHeal** reverts any manual `kubectl` changes that drift from the declared state

Rollback is a `git revert` — ArgoCD will detect the change and reconcile.

### Data bootstrap (manual, one-time)

First-time data load is handled by `bootstrap.yml`, a manually triggered `workflow_dispatch` workflow. It creates ephemeral pods with the required SQL client tools, restores Odoo and osTicket databases from gzipped SQL dumps, and syncs the Odoo filestore to EFS — all without requiring direct cluster access from a developer machine.

---

## Prerequisites

```bash
aws sts get-caller-identity   # authenticated to target account
terraform -version            # 1.7.x+
kubectl version --client
helm version                  # 3.x
```

Also required: `bash`, `jq`, `perl`. Docker only if you need to build/push a new application image.

---

## Outputs

After a full apply:

```bash
terraform -chdir=terraform/lz2-orchestration output application_access_urls
terraform -chdir=terraform/lz2-orchestration output -raw public_alb_dns_name
```

---

## VPN Access

Generate a client profile after every full rebuild (endpoint certificates change):

```bash
./scripts/generate-vpn-profile.sh --output "$HOME/Downloads/esm-vpn.ovpn"
```

Import into AWS VPN Client, connect, then test:

```bash
curl -I http://odoo.internal.esm.local/
curl -I http://moodle.internal.esm.local/
curl -I http://osticket.internal.esm.local/
```

---

## Repo Layout

```
terraform/
├── lz0-storage/          # Level 0: S3 state, DynamoDB lock, CloudTrail
├── lz1-network/          # Level 1: VPC, subnets, security groups, VPN
├── lz2-orchestration/    # Level 2: EKS, RDS, EFS, ALB, DNS, WAF, secrets, IRSA
└── modules/              # Shared modules: vpc, eks, rds, efs, alb, dns, waf, backup, monitoring, vpn

helm/
├── argocd-apps/          # App-of-Apps parent chart
├── odoo/                 # Deploys odoo-private and odoo-public via instance value
├── moodle/
└── osticket/

argocd/
└── bootstrap.yaml        # Parent Application CRD applied once to seed ArgoCD

scripts/
├── apply-landing-zones.sh
├── destroy-landing-zones.sh
├── deploy-odoo-image-to-eks.sh
├── destroy-everything.sh
├── generate-vpn-profile.sh
└── install-argocd.sh

.github/workflows/
├── terraform.yml         # Plan on PR, apply on merge
├── k8s-lint.yml          # helm lint + kube-linter
├── k8s-validate.yml      # kubeconform + HPA checks
├── security-and-deploy.yml
└── bootstrap.yml         # Manual data restore workflow
```

---

## Notes

- `.env` is for local convenience only. Never commit it.
- The Terraform state S3 bucket is excluded from teardown by design.
- `argocd/bootstrap.yaml` currently targets `feature/helm-charts`; update `targetRevision` to `main` before production go-live.
- Destroy demo stacks when not in use to control AWS cost.
