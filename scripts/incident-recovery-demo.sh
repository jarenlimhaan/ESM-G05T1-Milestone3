#!/usr/bin/env bash
# ==============================================================================
# Incident Detection & Recovery Demo
# ==============================================================================
# Simulates a pod failure in a target deployment and measures automatic
# recovery time. Optionally raises an osTicket incident ticket.
#
# Demonstrates:
#   - Kubernetes Deployment controller self-healing (pod recreated by ReplicaSet)
#   - liveness probe catching an unhealthy container and restarting it
#   - Recovery within 60 seconds (typical for healthy nodes)
#
# Usage:
#   ./scripts/incident-recovery-demo.sh \
#     [--namespace moodle-private] \
#     [--deployment moodle] \
#     [--osticket-url http://osticket.internal.esm.local] \
#     [--osticket-api-key <api-key>] \
#     [--osticket-email <staff-email>]
#
# Evidence captured:
#   - Pod name before deletion
#   - Deletion timestamp (T0)
#   - Recovery timestamp (T1) — when replacement pod is Running/Ready
#   - Total recovery time in seconds
#   - osTicket ticket number (if --osticket-url is provided)
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# Defaults
# ------------------------------------------------------------------------------
NAMESPACE="moodle-private"
DEPLOYMENT="moodle"
RECOVERY_TIMEOUT=120   # seconds to wait before declaring failure

# ------------------------------------------------------------------------------
# Argument parsing
# ------------------------------------------------------------------------------
usage() {
  cat <<'EOF'
Incident Detection & Recovery Demo

Usage:
  ./scripts/incident-recovery-demo.sh \
    [--namespace moodle-private] \
    [--deployment moodle]

Options:
  --namespace   Kubernetes namespace to target (default: moodle-private)
  --deployment  Deployment name inside the namespace (default: moodle)
  -h, --help    Show this help

Example:
  ./scripts/incident-recovery-demo.sh
  ./scripts/incident-recovery-demo.sh --namespace osticket-private --deployment osticket
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)    NAMESPACE="$2";      shift 2 ;;
    --deployment)   DEPLOYMENT="$2";     shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' not found." >&2
    exit 1
  fi
}

hr() { printf '%.0s=' {1..72}; echo; }

require_cmd kubectl

# ------------------------------------------------------------------------------
# Pre-flight: verify deployment exists and is healthy
# ------------------------------------------------------------------------------
hr
echo "  ESM Enterprise — Incident Detection & Recovery Demo"
hr
echo "  Target: deployment/${DEPLOYMENT}  namespace: ${NAMESPACE}"
echo "  Date:   $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
hr

echo ""
echo "[1/6] Verifying deployment is healthy before starting..."
DESIRED=$(kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
  -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "")
if [[ -z "${DESIRED}" ]]; then
  echo "Error: deployment '${DEPLOYMENT}' not found in namespace '${NAMESPACE}'." >&2
  exit 1
fi
READY=$(kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
  -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
echo "  Desired replicas : ${DESIRED}"
echo "  Ready replicas   : ${READY:-0}"
if [[ "${READY:-0}" -lt "${DESIRED}" ]]; then
  echo "Warning: deployment is not fully ready before the test. Proceeding anyway."
fi

# ------------------------------------------------------------------------------
# Pick one running pod to kill
# ------------------------------------------------------------------------------
echo ""
echo "[2/6] Selecting a pod to terminate (simulating incident)..."
POD_TO_KILL=$(kubectl get pods -n "${NAMESPACE}" \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -z "${POD_TO_KILL}" ]]; then
  echo "Error: no Running pods found in ${NAMESPACE}." >&2
  exit 1
fi
echo "  Pod selected: ${POD_TO_KILL}"

# Capture creation timestamp and node of the doomed pod for the report
POD_NODE=$(kubectl get pod "${POD_TO_KILL}" -n "${NAMESPACE}" \
  -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "unknown")
echo "  Node:         ${POD_NODE}"

# ------------------------------------------------------------------------------
# Record baseline pod list so we can identify the replacement
# ------------------------------------------------------------------------------
echo ""
echo "[3/6] Capturing baseline pod list..."
kubectl get pods -n "${NAMESPACE}"

# ------------------------------------------------------------------------------
# Delete the pod — T0
# ------------------------------------------------------------------------------
echo ""
echo "[4/6] Deleting pod '${POD_TO_KILL}' to simulate incident..."
T0=$(date +%s)
T0_HUMAN=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
kubectl delete pod "${POD_TO_KILL}" -n "${NAMESPACE}" --grace-period=0 --force 2>/dev/null || \
  kubectl delete pod "${POD_TO_KILL}" -n "${NAMESPACE}"
echo "  [T0] Incident triggered at: ${T0_HUMAN}"

# ------------------------------------------------------------------------------
# Wait for full recovery — T1
# ------------------------------------------------------------------------------
echo ""
echo "[5/6] Watching recovery (timeout ${RECOVERY_TIMEOUT}s)..."
echo "  Kubernetes Deployment controller will schedule a replacement pod."
echo "  liveness probe will confirm the container is healthy before marking Ready."
echo ""

RECOVERED=false
WAITED=0
POLL_INTERVAL=3

while [[ ${WAITED} -lt ${RECOVERY_TIMEOUT} ]]; do
  CURRENT_READY=$(kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  printf "\r  [+%3ds] Ready: %s/%s pods " "${WAITED}" "${CURRENT_READY:-0}" "${DESIRED}"
  if [[ "${CURRENT_READY:-0}" -ge "${DESIRED}" ]]; then
    RECOVERED=true
    break
  fi
  sleep ${POLL_INTERVAL}
  WAITED=$((WAITED + POLL_INTERVAL))
done
echo ""

T1=$(date +%s)
T1_HUMAN=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
RECOVERY_SECS=$((T1 - T0))

# ------------------------------------------------------------------------------
# Final pod state
# ------------------------------------------------------------------------------
echo ""
echo "[6/6] Final pod state:"
kubectl get pods -n "${NAMESPACE}" -o wide

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo ""
hr
echo "  INCIDENT RECOVERY SUMMARY"
hr
echo "  Namespace:      ${NAMESPACE}"
echo "  Deployment:     ${DEPLOYMENT}"
echo "  Pod killed:     ${POD_TO_KILL}"
echo "  Node:           ${POD_NODE}"
echo "  [T0] Incident:  ${T0_HUMAN}"
echo "  [T1] Recovered: ${T1_HUMAN}"
echo "  Recovery time:  ${RECOVERY_SECS} seconds"
if [[ "${RECOVERED}" == "true" ]]; then
  echo "  Result:         PASS — all ${DESIRED} replicas healthy within ${RECOVERY_SECS}s"
else
  echo "  Result:         FAIL — deployment did not fully recover within ${RECOVERY_TIMEOUT}s"
fi
hr

echo ""
if [[ "${RECOVERED}" != "true" ]]; then
  exit 1
fi
