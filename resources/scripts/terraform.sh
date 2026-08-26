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
script_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

#==============================================================================
# TERRAFORM TOOL EXECUTION
#==============================================================================

run_terraform() {
  "$script_directory/tool-container.sh" "$terraform_image" -chdir="$terraform_directory" "$@"
}

#==============================================================================
# TERRAFORM ACTION ROUTING
#==============================================================================

case "$action" in
  validate)
    run_terraform fmt -check -recursive
    run_terraform init -backend=false -input=false
    run_terraform validate
    ;;
  plan)
    run_terraform init -input=false
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