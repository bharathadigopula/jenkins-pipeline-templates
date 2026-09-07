#!/usr/bin/env bash

#==============================================================================
# TERRAFORM PIPELINE OPERATIONS
#==============================================================================

#==============================================================================
# SHELL SAFETY
#==============================================================================

set -euo pipefail

#==============================================================================
# TERRAFORM INPUTS
#==============================================================================

action="${1:-validate}"
terraform_directory="${TERRAFORM_DIRECTORY:-.}"
plan_file="${TERRAFORM_PLAN_FILE:-tfplan}"
terraform_image="${TERRAFORM_IMAGE:-hashicorp/terraform:1.15.9}"
backend_config_file="${TERRAFORM_BACKEND_CONFIG_FILE:-}"
script_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

#==============================================================================
# TERRAFORM TOOL EXECUTION
#==============================================================================

run_terraform() {
  "$script_directory/tool-container.sh" "$terraform_image" -chdir="$terraform_directory" "$@"
}

#==============================================================================
# TERRAFORM CACHE CLEANUP
#==============================================================================

clean_terraform_cache() {
  TOOL_CONTAINER_USER=0:0 \
    TOOL_CONTAINER_ENTRYPOINT=/bin/sh \
    "$script_directory/tool-container.sh" "$terraform_image" \
    -c "rm -rf -- \"\$1\"" _ "$terraform_directory/.terraform"
}

#==============================================================================
# TERRAFORM ACTION ROUTING
#==============================================================================

case "$action" in
  validate)
    clean_terraform_cache
    run_terraform fmt -check -recursive
    run_terraform init -upgrade -backend=false -input=false
    run_terraform validate
    ;;
  plan)
    init_arguments=(init -input=false)
    if [[ -n "$backend_config_file" ]]; then
      init_arguments+=("-backend-config=$backend_config_file")
    fi
    run_terraform "${init_arguments[@]}"
    run_terraform plan -input=false -out="$plan_file"
    sha256sum "$terraform_directory/$plan_file" | tee "$terraform_directory/$plan_file.sha256"
    ;;
  apply)
    : "${TERRAFORM_APPROVED_PLAN_SHA256:?TERRAFORM_APPROVED_PLAN_SHA256 is required}"
    actual_sha256=$(sha256sum "$terraform_directory/$plan_file" | cut -d' ' -f1)
    recorded_sha256=$(cut -d' ' -f1 "$terraform_directory/$plan_file.sha256")
    if [[ "$actual_sha256" == "$recorded_sha256" && "$actual_sha256" == "$TERRAFORM_APPROVED_PLAN_SHA256" ]]; then
      printf 'Saved Terraform plan checksum is approved.\n'
    else
      printf 'Saved Terraform plan checksum does not match approval.\n' >&2
      exit 1
    fi
    run_terraform apply -input=false "$plan_file"
    ;;
  *)
    printf 'Usage: %s validate|plan|apply\n' "$0" >&2
    exit 2
    ;;
esac

#==============================================================================
# TERRAFORM RESULT
#==============================================================================

printf 'terraform_%s=ready\n' "${action//-/_}"