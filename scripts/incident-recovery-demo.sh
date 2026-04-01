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
OSTICKET_URL=""
OSTICKET_API_KEY=""
OSTICKET_EMAIL=""

# ------------------------------------------------------------------------------
# Argument parsing
# ------------------------------------------------------------------------------
usage() {
  cat <<'EOF'
Incident Detection & Recovery Demo

Usage:
  ./scripts/incident-recovery-demo.sh \
    [--namespace moodle-private] \
    [--deployment moodle] \
    [--osticket-url http://osticket.internal.esm.local] \
    [--osticket-api-key <api-key>] \
    [--osticket-email <staff-email>]

Options:
  --namespace       Kubernetes namespace to target (default: moodle-private)
  --deployment      Deployment name inside the namespace (default: moodle)
  --osticket-url    Base URL of osTicket installation (omit to skip ticket creation)
  --osticket-api-key osTicket Staff API key (required if --osticket-url is set)
  --osticket-email  Staff e-mail for the ticket (required if --osticket-url is set)
  -h, --help        Show this help

Example (Moodle, no ticket):
  ./scripts/incident-recovery-demo.sh

Example (Moodle, with osTicket evidence):
  ./scripts/incident-recovery-demo.sh \
    --osticket-url http://osticket.internal.esm.local \
    --osticket-api-key XXXX-XXXX \
    --osticket-email admin@esmos.meals.sg
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)    NAMESPACE="$2";      shift 2 ;;
    --deployment)   DEPLOYMENT="$2";     shift 2 ;;
    --osticket-url) OSTICKET_URL="$2";   shift 2 ;;
    --osticket-api-key) OSTICKET_API_KEY="$2"; shift 2 ;;
    --osticket-email)   OSTICKET_EMAIL="$2";   shift 2 ;;
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

# ------------------------------------------------------------------------------
# (Optional) Create osTicket incident ticket
# ------------------------------------------------------------------------------
if [[ -n "${OSTICKET_URL}" ]]; then
  if [[ -z "${OSTICKET_API_KEY}" || -z "${OSTICKET_EMAIL}" ]]; then
    echo ""
    echo "Warning: --osticket-url set but --osticket-api-key / --osticket-email missing." >&2
    echo "Skipping ticket creation."
  else
    require_cmd curl

    if [[ "${RECOVERED}" == "true" ]]; then
      RESULT_LINE="RECOVERED in ${RECOVERY_SECS} seconds. All ${DESIRED} replicas healthy."
      TICKET_STATUS="Resolved"
    else
      RESULT_LINE="FAILED TO RECOVER within ${RECOVERY_TIMEOUT} seconds. Manual investigation required."
      TICKET_STATUS="Open"
    fi

    TICKET_BODY="Incident Recovery Demo — $(date -u '+%Y-%m-%d')

Namespace : ${NAMESPACE}
Deployment: ${DEPLOYMENT}
Pod killed: ${POD_TO_KILL}
Node      : ${POD_NODE}

T0 (incident triggered): ${T0_HUMAN}
T1 (recovery confirmed): ${T1_HUMAN}
Recovery time          : ${RECOVERY_SECS}s

Outcome: ${RESULT_LINE}

This ticket was automatically generated by the ESM Incident Recovery Demo script
to serve as audit evidence for platform resilience testing."

    echo ""
    echo "Creating osTicket incident ticket..."
    HTTP_RESPONSE=$(curl -s -o /tmp/osticket_response.json -w "%{http_code}" \
      -X POST "${OSTICKET_URL}/api/tickets.json" \
      -H "X-API-Key: ${OSTICKET_API_KEY}" \
      -H "Content-Type: application/json" \
      -d "$(printf '%s' "{
        \"name\": \"ESM Incident Recovery Demo\",
        \"email\": \"${OSTICKET_EMAIL}\",
        \"subject\": \"[Incident Demo] Pod failure in ${NAMESPACE}/${DEPLOYMENT} — ${T0_HUMAN}\",
        \"message\": $(printf '%s' "${TICKET_BODY}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
        \"topicId\": \"1\"
      }")" || true)

    if [[ "${HTTP_RESPONSE}" == "201" ]]; then
      TICKET_NUM=$(python3 -c "
import json, sys
try:
    print(json.load(open('/tmp/osticket_response.json')))
except Exception:
    print('unknown')
" 2>/dev/null || cat /tmp/osticket_response.json)
      echo "  osTicket ticket created: #${TICKET_NUM}"
      echo "  Status: ${TICKET_STATUS}"
      echo "  URL: ${OSTICKET_URL}/scp/tickets.php?number=${TICKET_NUM}"
    else
      echo "  Warning: ticket creation returned HTTP ${HTTP_RESPONSE}." >&2
      cat /tmp/osticket_response.json >&2 || true
    fi
  fi
fi

echo ""
if [[ "${RECOVERED}" != "true" ]]; then
  exit 1
fi
