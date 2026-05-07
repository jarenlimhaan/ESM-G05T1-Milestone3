# Kubernetes Workloads

This folder contains the source Kubernetes manifests. Some values are placeholders and must be rendered from Terraform outputs before apply.

## Structure

- `namespace.yaml`: Namespace definitions.
- `secrets.yaml`: Kubernetes Secret template rendered by scripts.
- `storage/odoo-storage.yaml`: EFS-backed Odoo PV/PVC.
- `odoo/`: Odoo deployments, services, ingress, and HPA.
- `moodle/`: Moodle deployment, service, ingress, and HPA.
- `osticket/`: osTicket deployment, service, ingress, and HPA.

## Apply

Preferred full flow:

```bash
./scripts/apply-landing-zones.sh \
  --aws-region ap-southeast-1 \
  --odoo-db-password "$ODOO_DB_PASSWORD" \
  --moodle-db-password "$MOODLE_DB_PASSWORD" \
  --osticket-db-password "$OSTICKET_DB_PASSWORD" \
  --osticket-install-secret "$INSTALL_SECRET" \
  --osticket-admin-password "$ADMIN_PASSWORD"
```

Kubernetes-only reapply after infrastructure already exists:

```bash
./scripts/deploy-k8s-apps.sh \
  --terraform-dir terraform/lz2-orchestration \
  --aws-region ap-southeast-1
```

Do not run raw `kubectl apply -k k8s` because placeholders will not be replaced.

## Render For ArgoCD

```bash
./scripts/render-k8s-for-argocd.sh --aws-region ap-southeast-1
```

ArgoCD should watch `k8s-rendered/`, not this raw `k8s/` folder.
