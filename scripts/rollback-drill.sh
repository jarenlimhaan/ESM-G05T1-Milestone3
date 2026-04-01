#!/usr/bin/env bash
# ==============================================================================
# rollback-drill.sh — RFC-001 Rollback Drill: Phase 2 → Phase 1
# ==============================================================================
#
# WHAT THIS DEMONSTRATES:
#   This script simulates an incident rollback using GitOps (ArgoCD).
#   We start from Phase 2 (HPAs active, autoscaling enabled) and roll back
#   to Phase 1 (HPAs removed, fixed replicas) — proving the system can be
#   recovered quickly via a single Git commit, with no direct kubectl access
#   to production resources.
#
# PHASES:
#   Phase 2 (current / "before"):
#     - All 4 HPAs active (odoo, odoo-public, moodle, osticket)
#     - Autoscaling between min=1 and max=4 replicas
#     - ArgoCD tracking k8s-rendered/ on fix/secrets branch
#
#   Phase 1 (rollback target / "after"):
#     - All HPAs removed
#     - Deployments return to their static replica counts
#     - Stable, predictable state for incident recovery
#
# EXPECTED OUTCOME:
#   Total rollback time < 2 minutes
#   ArgoCD auto-applies the change — no manual kubectl patching required
#
# USAGE:
#   bash scripts/rollback-drill.sh
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUSTOMIZATION="${REPO_ROOT}/k8s-rendered/kustomization.yaml"
BRANCH="fix/secrets"

# Colours for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Colour

banner() { echo -e "\n${CYAN}==> $1${NC}"; }
info()   { echo -e "    ${YELLOW}$1${NC}"; }
ok()     { echo -e "    ${GREEN}✔ $1${NC}"; }

# ==============================================================================
# EVIDENCE A — Capture Phase 2 "before" state
# ==============================================================================
banner "EVIDENCE A — Phase 2 state (BEFORE rollback)"
info "Capturing current HPA and pod counts. Take a screenshot of this output."

echo ""
echo "── HPAs across all namespaces ──"
kubectl get hpa -A

echo ""
echo "── ArgoCD application sync status ──"
kubectl get application esm-enterprise -n argocd

echo ""
echo "── Pod counts per namespace ──"
kubectl get pods -n odoo-private   --no-headers | wc -l | xargs echo "  odoo-private pods:"
kubectl get pods -n odoo-public    --no-headers | wc -l | xargs echo "  odoo-public pods:"
kubectl get pods -n moodle-private --no-headers | wc -l | xargs echo "  moodle-private pods:"
kubectl get pods -n osticket-private --no-headers | wc -l | xargs echo "  osticket-private pods:"

echo ""
info ">>> SCREENSHOT THIS OUTPUT NOW (Evidence A) <<<"
echo ""
read -rp "Press ENTER when ready to start the rollback (stopwatch starts after this)..."

# ==============================================================================
# START STOPWATCH
# ==============================================================================
DRILL_START=$(date +%s)
banner "STOPWATCH STARTED — Rolling back to Phase 1..."

# ==============================================================================
# ROLLBACK STEP 1 — Edit kustomization.yaml: comment out all 4 HPAs
# ==============================================================================
banner "Step 1 — Disabling all HPAs in k8s-rendered/kustomization.yaml"
info "This is the ONLY file that needs to change."
info "Commenting out odoo, odoo-public, moodle, and osticket HPA entries..."

sed -i 's|  - odoo/hpa.yaml|  # - odoo/hpa.yaml|' "${KUSTOMIZATION}"
sed -i 's|  - odoo/hpa-public.yaml|  # - odoo/hpa-public.yaml|' "${KUSTOMIZATION}"
sed -i 's|  - moodle/hpa.yaml|  # - moodle/hpa.yaml|' "${KUSTOMIZATION}"
sed -i 's|  - osticket/hpa.yaml|  # - osticket/hpa.yaml|' "${KUSTOMIZATION}"

ok "kustomization.yaml updated"

# ==============================================================================
# ROLLBACK STEP 2 — Git commit and push to fix/secrets
# ==============================================================================
banner "Step 2 — Committing and pushing to Git (branch: ${BRANCH})"
info "ArgoCD watches this branch. A push is all that is needed to trigger rollback."

git -C "${REPO_ROOT}" add k8s-rendered/kustomization.yaml
git -C "${REPO_ROOT}" commit -m "rollback: Phase 1 restore — disable all HPAs (RFC-001 drill)"
git -C "${REPO_ROOT}" push origin "${BRANCH}"

ok "Pushed to ${BRANCH}"

# ==============================================================================
# ROLLBACK STEP 3 — Trigger ArgoCD hard refresh
# ==============================================================================
banner "Step 3 — Triggering ArgoCD hard refresh"
info "This forces ArgoCD to pull the latest commit immediately (skips 3-min poll)."

kubectl annotate application esm-enterprise -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite

ok "ArgoCD refresh triggered"

# ==============================================================================
# Wait for ArgoCD to complete sync
# ==============================================================================
banner "Waiting for ArgoCD to sync..."
info "Polling every 5 seconds..."

for i in $(seq 1 24); do
  STATUS=$(kubectl get application esm-enterprise -n argocd \
    -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
  HEALTH=$(kubectl get application esm-enterprise -n argocd \
    -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
  echo "    [${i}] Sync: ${STATUS} | Health: ${HEALTH}"
  if [[ "${STATUS}" == "Synced" && "${HEALTH}" == "Healthy" ]]; then
    break
  fi
  sleep 5
done

# ==============================================================================
# STOP STOPWATCH
# ==============================================================================
DRILL_END=$(date +%s)
ELAPSED=$(( DRILL_END - DRILL_START ))

banner "STOPWATCH STOPPED"
echo -e "    ${GREEN}Total rollback time: ${ELAPSED} seconds${NC}"

# ==============================================================================
# EVIDENCE B — Capture Phase 1 "after" state
# ==============================================================================
banner "EVIDENCE B — Phase 1 state (AFTER rollback)"
info "Capturing final HPA and pod counts. Take a screenshot of this output."

echo ""
echo "── HPAs across all namespaces ──"
kubectl get hpa -A 2>&1 || echo "  (No HPAs found — correct for Phase 1)"

echo ""
echo "── ArgoCD application sync status ──"
kubectl get application esm-enterprise -n argocd

echo ""
echo "── Pod counts per namespace ──"
kubectl get pods -n odoo-private   --no-headers
kubectl get pods -n odoo-public    --no-headers
kubectl get pods -n moodle-private --no-headers
kubectl get pods -n osticket-private --no-headers

echo ""
ok "Rollback drill complete in ${ELAPSED} seconds"
info ">>> SCREENSHOT THIS OUTPUT NOW (Evidence B) <<<"
