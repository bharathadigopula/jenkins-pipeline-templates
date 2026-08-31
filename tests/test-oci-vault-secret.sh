#!/usr/bin/env bash

#==============================================================================
# OCI VAULT SECRET RETRIEVAL TEST
#==============================================================================

#==============================================================================
# SHELL SAFETY
#==============================================================================

set -euo pipefail

#==============================================================================
# TEST WORKSPACE
#==============================================================================

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT
install -d "$temporary_directory/bin"

#==============================================================================
# OCI TEST DOUBLE
#==============================================================================

cat > "$temporary_directory/bin/oci" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$OCI_VAULT_TEST_CALLS"

case "$1 $2 $3" in
  'vault secret list')
    printf '{"data":[{"id":"ocid1.vaultsecret.oc1.test"}]}\n'
    ;;
  'secrets secret-bundle get')
    content=$(printf '%s' '{"tenancy_ocid":"ocid1.tenancy.oc1..test"}' | base64)
    jq -cn --arg content "$content" '{data: {"secret-bundle-content": {content: $content}}}'
    ;;
  *)
    printf 'Unexpected OCI command.\n' >&2
    exit 1
    ;;
esac
EOF
chmod +x "$temporary_directory/bin/oci"

#==============================================================================
# TEST EXECUTION
#==============================================================================

export OCI_CLI_CONTAINER_READY=true
export OCI_VAULT_COMPARTMENT_OCID=ocid1.compartment.oc1..test
export OCI_VAULT_REGION=ap-hyderabad-1
export OCI_VAULT_SECRET_NAME=bharathcloudops-prd-hyd-terraform-credentials
export OCI_VAULT_TEST_CALLS="$temporary_directory/oci-calls"
export PATH="$temporary_directory/bin:$PATH"
export TERRAFORM_CREDENTIAL_FILE="$temporary_directory/terraform-credentials.json"

output=$(bash "$repository_root/resources/scripts/oci-vault-secret.sh")

#==============================================================================
# TEST ASSERTIONS
#==============================================================================

if [[ "$output" != "oci_vault_secret=ready" ]]; then
  printf 'OCI Vault retrieval did not report readiness.\n' >&2
  exit 1
fi

jq -e '.tenancy_ocid == "ocid1.tenancy.oc1..test"' "$TERRAFORM_CREDENTIAL_FILE" >/dev/null
if stat --version >/dev/null 2>&1; then
  credential_mode=$(stat -c '%a' "$TERRAFORM_CREDENTIAL_FILE")
else
  credential_mode=$(stat -f '%Lp' "$TERRAFORM_CREDENTIAL_FILE")
fi
if [[ "$credential_mode" != "600" ]]; then
  printf 'OCI Vault credential file permissions are not 0600.\n' >&2
  exit 1
fi

if grep -Fq 'tenancy_ocid' "$OCI_VAULT_TEST_CALLS"; then
  printf 'OCI Vault credential content leaked into command arguments.\n' >&2
  exit 1
fi

grep -Fq -- '--auth instance_principal' "$OCI_VAULT_TEST_CALLS"
printf 'oci_vault_secret_test=ready\n'