# Kubernetes Workloads

This folder contains Kubernetes manifests for the application workloads and the autoscaling components they depend on.

## Structure

- `namespace.yaml`: Namespace definition for the apps.
- `secrets.yaml`: Database credentials template (rendered by script).
- `storage/odoo-storage.yaml`: Static EFS PV and PVC for Odoo.
- `odoo/`: Odoo deployment and service.
- `moodle/`: Moodle deployment and service.
- `osticket/`: osTicket deployment and service.
- `odoo/ingress-public.yaml`: internet-facing ALB ingress for public Odoo routes.
- `odoo/ingress-internal.yaml`: internal ALB ingress for private Odoo backend.
- `moodle/ingress-internal.yaml`: internal ALB ingress for Moodle.
- `osticket/ingress-internal.yaml`: internal ALB ingress for osTicket.

## Deploy

From the repository root:

```powershell
./scripts/deploy-k8s-apps.ps1 `
  -OdooDbPassword "<odoo-password>" `
  -MoodleDbPassword "<moodle-password>"
```

```bash
./scripts/deploy-k8s-apps.sh \
  --moodle-image "ellakcy/moodle:mysql_maria_apache_latest" \
  --moodle-admin-user "admin" \
  --moodle-admin-password "Admin~1234" \
  --moodle-admin-email "admin@esmos.meals.sg" \
  --moodle-url "http://moodle.internal.esm.local" \
  --odoo-db-password "<odoo-password>" \
  --moodle-db-password "<moodle-password>" \
  --osticket-db-password "<osticket-password>"
```

The script:

1. Reads infrastructure values from Terraform outputs.
2. Updates `kubeconfig` for the EKS cluster.
3. Renders manifest placeholders into a temporary directory.
4. Runs `kubectl apply -k` against the rendered manifests.
5. Restarts deployments and verifies rollout.
6. Checks Moodle DB install state and auto-repairs if `mdl_config.version` is missing.

Do not run `kubectl apply -k k8s` directly unless placeholders are already rendered.

For full project rebuild (destroy + infra + image push + deploy + bootstrap), use:

```bash
./scripts/rebuild-from-scratch.sh
```

After deployment, get access endpoints:

```powershell
kubectl get ingress -A
```

## Prerequisites

- `terraform` state already applied in `terraform/`.
- `aws` CLI authenticated with access to EKS.
- `kubectl` installed and reachable.
- AWS Load Balancer Controller installed in the EKS cluster for `ingressClassName: alb`.
