# Rendered Kubernetes Workloads

This folder contains rendered Kubernetes manifests for ArgoCD. It is generated from `k8s/` plus Terraform outputs from `terraform/lz2-orchestration`.

Regenerate after infrastructure values or app manifests change:

```bash
./scripts/render-k8s-for-argocd.sh --aws-region ap-southeast-1
```

Then commit and push the rendered changes so ArgoCD can reconcile them.

Do not hand-edit rendered files unless you intentionally want the rendered output to differ from `k8s/`.
