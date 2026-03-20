#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/generate-vpn-profile.sh \
    [--terraform-dir terraform] \
    [--output ~/Downloads/esm-vpn-config-fixed.ovpn]

Options:
  --terraform-dir  Terraform directory (default: terraform).
  --output         Output .ovpn path (default: ~/Downloads/esm-vpn-config-fixed.ovpn).
  -h, --help       Show help.

This script:
1. Reads VPN endpoint/region from Terraform outputs.
2. Exports AWS Client VPN config (.ovpn).
3. Injects <ca>, <cert>, and <key> from Terraform state for certificate auth.
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' not found." >&2
    exit 1
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TERRAFORM_DIR="${REPO_ROOT}/terraform"
OUTPUT_FILE="${HOME}/Downloads/esm-vpn-config-fixed.ovpn"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --terraform-dir)
      TERRAFORM_DIR="$2"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "${TERRAFORM_DIR}" != /* ]]; then
  TERRAFORM_DIR="${REPO_ROOT}/${TERRAFORM_DIR}"
fi

require_cmd terraform
require_cmd aws
require_cmd jq
require_cmd perl

mkdir -p "$(dirname "${OUTPUT_FILE}")"

echo "Reading VPN endpoint details from Terraform outputs..."
VPN_ID="$(terraform -chdir="${TERRAFORM_DIR}" output -raw vpn_endpoint_id)"
AWS_REGION="$(terraform -chdir="${TERRAFORM_DIR}" output -raw aws_region)"

RAW_FILE="$(mktemp "${TMPDIR:-/tmp}/esm-vpn-raw-XXXXXX.ovpn")"
trap 'rm -f "${RAW_FILE}"' EXIT

echo "Exporting raw VPN configuration for endpoint ${VPN_ID}..."
aws ec2 export-client-vpn-client-configuration \
  --region "${AWS_REGION}" \
  --client-vpn-endpoint-id "${VPN_ID}" \
  --output text > "${RAW_FILE}"

echo "Reading TLS materials from Terraform state..."
STATE_JSON="$(terraform -chdir="${TERRAFORM_DIR}" state pull)"

CLIENT_KEY="$(printf '%s' "${STATE_JSON}" | jq -r '.resources[] | select(.module=="module.vpn" and .type=="tls_private_key" and .name=="vpn_client") | .instances[0].attributes.private_key_pem')"
CLIENT_CERT="$(printf '%s' "${STATE_JSON}" | jq -r '.resources[] | select(.module=="module.vpn" and .type=="tls_locally_signed_cert" and .name=="vpn_client") | .instances[0].attributes.cert_pem')"
CA_CERT="$(printf '%s' "${STATE_JSON}" | jq -r '.resources[] | select(.module=="module.vpn" and .type=="tls_self_signed_cert" and .name=="vpn_server") | .instances[0].attributes.cert_pem')"

if [[ -z "${CLIENT_KEY}" || "${CLIENT_KEY}" == "null" || -z "${CLIENT_CERT}" || "${CLIENT_CERT}" == "null" || -z "${CA_CERT}" || "${CA_CERT}" == "null" ]]; then
  echo "Error: failed to read VPN TLS materials from Terraform state." >&2
  exit 1
fi

BASE_CONFIG="$(perl -0777 -pe 's#(?s)<ca>.*?</ca>\s*##g; s#(?s)<cert>.*?</cert>\s*##g; s#(?s)<key>.*?</key>\s*##g;' "${RAW_FILE}")"

cat > "${OUTPUT_FILE}" <<EOF
${BASE_CONFIG}

<ca>
${CA_CERT}
</ca>
<cert>
${CLIENT_CERT}
</cert>
<key>
${CLIENT_KEY}
</key>
EOF

chmod 600 "${OUTPUT_FILE}" || true
echo "Created VPN profile: ${OUTPUT_FILE}"
echo "Import this file into AWS VPN Client and reconnect."
