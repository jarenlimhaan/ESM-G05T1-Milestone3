# Kubernetes Workloads

This folder contains Kubernetes manifests for application workloads only.

## Structure

- `namespace.yaml`: Namespace definition for the apps.
- `secrets.yaml`: Database credentials template (rendered by script).
- `storage/odoo-storage.yaml`: Static EFS PV and PVC for Odoo.
- `odoo/`: Odoo deployment and service.
- `moodle/`: Moodle deployment and service.
- `odoo/service-public.yaml`, `moodle/service-public.yaml`: internet-facing NLB services.
- `odoo/service-vpn.yaml`, `moodle/service-vpn.yaml`: internal NLB services for VPN clients.

## Deploy

From the repository root:

```powershell
./scripts/deploy-k8s-apps.ps1 `
  -OdooDbPassword "<odoo-password>" `
  -MoodleDbPassword "<moodle-password>"
```

The script:

1. Reads infrastructure values from Terraform outputs.
2. Updates `kubeconfig` for the EKS cluster.
3. Renders manifest placeholders into a temporary directory.
4. Runs `kubectl apply -k` against the rendered manifests.

After deployment, get access endpoints:

```powershell
kubectl get svc -n esm odoo-public odoo-vpn moodle-public moodle-vpn
```

## Prerequisites

- `terraform` state already applied in `terraform/`.
- `aws` CLI authenticated with access to EKS.
- `kubectl` installed and reachable.
- AWS Load Balancer Controller installed in the EKS cluster for `ingressClassName: alb`.
