#!/usr/bin/env bash

#==============================================================================
# OCI VAULT SECRET RETRIEVAL
#==============================================================================

#==============================================================================
# SHELL SAFETY
#==============================================================================

set -euo pipefail

#==============================================================================
# VAULT INPUTS
#==============================================================================

secret_name="${OCI_VAULT_SECRET_NAME:-}"
compartment_ocid="${OCI_VAULT_COMPARTMENT_OCID:-}"
region="${OCI_VAULT_REGION:-}"
credential_file="${TERRAFORM_CREDENTIAL_FILE:-}"
oci_cli_version="${OCI_CLI_VERSION:-3.91.0}"
python_image="${OCI_CLI_PYTHON_IMAGE:-python:3.11.13-slim}"

if [[ ! "$secret_name" =~ ^[a-z0-9][a-z0-9-]{2,127}$ ]] || \
  [[ ! "$compartment_ocid" =~ ^ocid1\.compartment\. ]] || \
  [[ ! "$region" =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]] || \
  [[ -z "$credential_file" ]]; then
  printf 'OCI Vault secret name, compartment, region, and credential file are required.\n' >&2
  exit 1
fi

#==============================================================================
# PINNED OCI CLI CONTAINER
#==============================================================================

if [[ "${OCI_CLI_CONTAINER_READY:-false}" != "true" ]]; then
  jenkins_container_id="${JENKINS_CONTAINER_ID:-${HOSTNAME:-}}"
  if [[ -z "$jenkins_container_id" ]]; then
    printf 'JENKINS_CONTAINER_ID or HOSTNAME is required.\n' >&2
    exit 1
  fi

  exec docker run --rm \
    --volumes-from "$jenkins_container_id" \
    --workdir "$PWD" \
    --network host \
    --env OCI_CLI_CONTAINER_READY=true \
    --env OCI_CLI_VERSION="$oci_cli_version" \
    --env OCI_VAULT_COMPARTMENT_OCID="$compartment_ocid" \
    --env OCI_VAULT_REGION="$region" \
    --env OCI_VAULT_SECRET_NAME="$secret_name" \
    --env TERRAFORM_CREDENTIAL_FILE="$credential_file" \
    "$python_image" \
    sh -c 'apt-get update >/dev/null && apt-get install --yes jq >/dev/null && python -m pip install --disable-pip-version-check --no-cache-dir "oci-cli==$OCI_CLI_VERSION" >/dev/null && bash "$1"' \
    _ "$0"
fi

#==============================================================================
# SECRET IDENTIFIER RESOLUTION
#==============================================================================

secret_ids=$(oci vault secret list \
  --auth instance_principal \
  --compartment-id "$compartment_ocid" \
  --region "$region" \
  --name "$secret_name" \
  --lifecycle-state ACTIVE \
  --all | jq -r '.data[].id')

if [[ "$(wc -w <<< "$secret_ids" | tr -d ' ')" != "1" ]]; then
  printf 'OCI Vault secret must resolve to exactly one active secret.\n' >&2
  exit 1
fi

secret_id="$secret_ids"

#==============================================================================
# SECRET CONTENT RETRIEVAL
#==============================================================================

install -m 0600 /dev/null "$credential_file"
oci secrets secret-bundle get \
  --auth instance_principal \
  --secret-id "$secret_id" \
  --stage CURRENT \
  --region "$region" | jq -r '.data."secret-bundle-content".content' | base64 --decode > "$credential_file"

if ! jq -e 'type == "object"' "$credential_file" >/dev/null; then
  rm -f "$credential_file"
  printf 'OCI Vault Terraform credential secret must contain a JSON object.\n' >&2
  exit 1
fi

printf 'oci_vault_secret=ready\n'