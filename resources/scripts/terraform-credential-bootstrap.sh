#!/usr/bin/env bash

#==============================================================================
# TERRAFORM CREDENTIAL BOOTSTRAP
#==============================================================================

set -euo pipefail

#==============================================================================
# BOOTSTRAP INPUTS
#==============================================================================

: "${TERRAFORM_CREDENTIAL_FILE:?TERRAFORM_CREDENTIAL_FILE is required}"
wordpress_registry_token="${WORDPRESS_REGISTRY_TOKEN:-}"

if [[ -z "$wordpress_registry_token" ]]; then
  printf 'terraform_credential_bootstrap=skipped\n'
  exit 0
fi
if [[ ${#wordpress_registry_token} -lt 20 || "$wordpress_registry_token" == *$'\n'* ]]; then
  printf 'WORDPRESS_REGISTRY_TOKEN must be a single-line token of at least 20 characters.\n' >&2
  exit 1
fi
if [[ ! -r "$TERRAFORM_CREDENTIAL_FILE" ]]; then
  printf 'TERRAFORM_CREDENTIAL_FILE must identify a readable file.\n' >&2
  exit 1
fi

#==============================================================================
# ATOMIC CREDENTIAL UPDATE
#==============================================================================

temporary_file=$(mktemp "${TERRAFORM_CREDENTIAL_FILE}.XXXXXX")
trap 'rm -f "$temporary_file"' EXIT
jq --arg token "$wordpress_registry_token" \
  '.wordpress_registry_token = $token' "$TERRAFORM_CREDENTIAL_FILE" > "$temporary_file"
chmod 0600 "$temporary_file"
mv "$temporary_file" "$TERRAFORM_CREDENTIAL_FILE"
trap - EXIT

printf 'terraform_credential_bootstrap=ready\n'