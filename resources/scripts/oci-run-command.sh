#!/usr/bin/env bash

#==============================================================================
# OCI RUN COMMAND PIPELINE OPERATIONS
#==============================================================================

#==============================================================================
# SHELL SAFETY
#==============================================================================

set -euo pipefail

#==============================================================================
# RUN COMMAND INPUTS
#==============================================================================

action="${OCI_RUN_COMMAND_ACTION:-validate}"
credentials_file="${OCI_CREDENTIALS_FILE:-}"
script_path="${RUN_COMMAND_SCRIPT_PATH:-}"
targets_json="${RUN_COMMAND_TARGETS:-[]}"
display_name="${RUN_COMMAND_DISPLAY_NAME:-jenkins-run-command}"
required_output_marker="${RUN_COMMAND_REQUIRED_OUTPUT_MARKER:-}"
timeout_seconds="${RUN_COMMAND_TIMEOUT_SECONDS:-300}"
vault_secret_name="${RUN_COMMAND_VAULT_SECRET_NAME:-}"
results_directory="${RUN_COMMAND_RESULTS_DIRECTORY:-run-command-results}"
oci_cli_version="${OCI_CLI_VERSION:-3.91.0}"
python_image="${OCI_CLI_PYTHON_IMAGE:-python:3.11.13-slim}"

#==============================================================================
# ACTION VALIDATION
#==============================================================================

case "$action" in
  validate|dry-run|deploy|upgrade|verify|backup|restore|rollback)
    ;;
  *)
    printf 'Unsupported OCI Run Command action: %s\n' "$action" >&2
    exit 2
    ;;
esac

#==============================================================================
# CREDENTIAL VALIDATION
#==============================================================================

if [[ ! -f "$credentials_file" ]]; then
  printf 'OCI_CREDENTIALS_FILE must identify an existing JSON file.\n' >&2
  exit 1
fi

if ! jq -e '
  type == "object" and
  (.tenancy_ocid | type == "string" and startswith("ocid1.tenancy.")) and
  (.user_ocid | type == "string" and startswith("ocid1.user.")) and
  (.fingerprint | type == "string" and length > 0) and
  (.private_key | type == "string" and contains("BEGIN PRIVATE KEY")) and
  (.region | type == "string" and test("^[a-z]{2}-[a-z]+-[0-9]+$")) and
  (.compartment_ocid | type == "string" and startswith("ocid1.compartment."))
' "$credentials_file" >/dev/null; then
  printf 'OCI credential JSON is invalid.\n' >&2
  exit 1
fi

#==============================================================================
# TARGET VALIDATION
#==============================================================================

if ! jq -e '
  type == "array" and
  length > 0 and
  all(.[ ];
    type == "object" and
    (.name | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")) and
    (.instance_id | type == "string" and startswith("ocid1.instance.")) and
    (.arguments | type == "array" and all(.[ ]; type == "string"))
  )
' <<< "$targets_json" >/dev/null; then
  printf 'RUN_COMMAND_TARGETS is invalid.\n' >&2
  exit 1
fi

if [[ ! -f "$script_path" ]]; then
  printf 'RUN_COMMAND_SCRIPT_PATH must identify an existing script.\n' >&2
  exit 1
fi

if [[ ! "$timeout_seconds" =~ ^[0-9]+$ ]] || (( timeout_seconds < 30 || timeout_seconds > 3600 )); then
  printf 'RUN_COMMAND_TIMEOUT_SECONDS must be between 30 and 3600.\n' >&2
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
    --env OCI_CLI_CONTAINER_READY=true \
    --env OCI_CLI_VERSION="$oci_cli_version" \
    --env OCI_CREDENTIALS_FILE="$credentials_file" \
    --env OCI_RUN_COMMAND_ACTION="$action" \
    --env RUN_COMMAND_DISPLAY_NAME="$display_name" \
    --env RUN_COMMAND_REQUIRED_OUTPUT_MARKER="$required_output_marker" \
    --env RUN_COMMAND_RESULTS_DIRECTORY="$results_directory" \
    --env RUN_COMMAND_SCRIPT_PATH="$script_path" \
    --env RUN_COMMAND_TARGETS="$targets_json" \
    --env RUN_COMMAND_TIMEOUT_SECONDS="$timeout_seconds" \
    --env RUN_COMMAND_VAULT_SECRET_NAME="$vault_secret_name" \
    "$python_image" \
    sh -c 'apt-get update >/dev/null && apt-get install --yes jq >/dev/null && python -m pip install --disable-pip-version-check --no-cache-dir "oci-cli==$OCI_CLI_VERSION" >/dev/null && bash "$1"' \
    _ "$0"
fi

#==============================================================================
# OCI CLI CONFIGURATION
#==============================================================================

configuration_directory="$PWD/.jenkins-oci"
install -d -m 0700 "$configuration_directory"
jq -r '.private_key' "$credentials_file" > "$configuration_directory/api_key.pem"
chmod 0600 "$configuration_directory/api_key.pem"

{
  printf '[DEFAULT]\n'
  printf 'user=%s\n' "$(jq -r '.user_ocid' "$credentials_file")"
  printf 'fingerprint=%s\n' "$(jq -r '.fingerprint' "$credentials_file")"
  printf 'tenancy=%s\n' "$(jq -r '.tenancy_ocid' "$credentials_file")"
  printf 'region=%s\n' "$(jq -r '.region' "$credentials_file")"
  printf 'key_file=%s\n' "$configuration_directory/api_key.pem"
} > "$configuration_directory/config"
chmod 0600 "$configuration_directory/config"

export OCI_CLI_CONFIG_FILE="$configuration_directory/config"
region=$(jq -r '.region' "$credentials_file")
compartment_ocid=$(jq -r '.compartment_ocid' "$credentials_file")

#==============================================================================
# OPTIONAL VAULT SECRET
#==============================================================================

secret_argument=""
if [[ -n "$vault_secret_name" ]]; then
  secret_ids=$(oci vault secret list \
    --compartment-id "$compartment_ocid" \
    --lifecycle-state ACTIVE \
    --name "$vault_secret_name" \
    --all | jq -r '.data[].id')

  if [[ "$(wc -w <<< "$secret_ids" | tr -d ' ')" != "1" ]]; then
    printf 'Vault secret name must resolve to exactly one active secret.\n' >&2
    exit 1
  fi

  secret_argument=$(oci secrets secret-bundle get \
    --secret-id "$secret_ids" \
    --stage CURRENT | jq -r '.data."secret-bundle-content".content' | base64 --decode)

  if [[ -z "$secret_argument" || "$secret_argument" == *$'\n'* ]]; then
    printf 'Vault secret must contain exactly one non-empty line.\n' >&2
    exit 1
  fi
fi

#==============================================================================
# RUN COMMAND DISPATCH
#==============================================================================

mkdir -p "$results_directory"
overall_exit_code=0

while IFS= read -r target; do
  target_name=$(jq -r '.name' <<< "$target")
  instance_id=$(jq -r '.instance_id' <<< "$target")
  arguments=$(jq -c --arg action "$action" '[$action] + .arguments' <<< "$target")

  if [[ -n "$secret_argument" ]]; then
    arguments=$(jq -c --arg secret_argument "$secret_argument" '. + [$secret_argument]' <<< "$arguments")
  fi

  argument_line=$(jq -r '[.[] | @sh] | "set -- " + join(" ")' <<< "$arguments")
  command_text=$(printf '%s\n%s' "$argument_line" "$(cat "$script_path")")
  command_size=$(printf '%s' "$command_text" | wc -c | tr -d ' ')

  if (( command_size > 4096 )); then
    printf 'Rendered command for %s exceeds the 4096-byte limit.\n' "$target_name" >&2
    overall_exit_code=1
    continue
  fi

  content=$(jq -n --arg text "$command_text" '{source: {sourceType: "TEXT", text: $text}, output: {outputType: "TEXT"}}')
  target_payload=$(jq -n --arg instance_id "$instance_id" '{instanceId: $instance_id}')
  response=$(oci instance-agent command create \
    --compartment-id "$compartment_ocid" \
    --content "$content" \
    --display-name "${display_name}-${target_name}" \
    --region "$region" \
    --target "$target_payload" \
    --timeout-in-seconds "$timeout_seconds")
  command_id=$(jq -r '.data.id' <<< "$response")

  if [[ -z "$command_id" || "$command_id" == "null" ]]; then
    printf 'OCI did not return a command OCID for %s.\n' "$target_name" >&2
    overall_exit_code=1
    continue
  fi

  printf 'Dispatched %s to %s as %s.\n' "$display_name" "$target_name" "$command_id"
  deadline=$(( $(date +%s) + timeout_seconds + 600 ))
  result_file="$results_directory/${target_name}.json"
  target_exit_code=1

  #============================================================================
  # RUN COMMAND MONITORING
  #============================================================================

  while (( $(date +%s) < deadline )); do
    execution=$(oci instance-agent command-execution get \
      --command-id "$command_id" \
      --instance-id "$instance_id" \
      --region "$region")
    lifecycle_state=$(jq -r '.data."lifecycle-state"' <<< "$execution")
    printf 'Target %s is %s.\n' "$target_name" "$lifecycle_state"

    case "$lifecycle_state" in
      SUCCEEDED)
        printf '%s\n' "$execution" > "$result_file"
        command_output=$(jq -r '.data.content.text // ""' <<< "$execution")
        if [[ -n "$required_output_marker" ]] && ! grep -Fq "$required_output_marker" <<< "$command_output"; then
          printf 'Required output marker is missing for %s.\n' "$target_name" >&2
        else
          target_exit_code=0
        fi
        break
        ;;
      FAILED|TIMED_OUT|CANCELED)
        printf '%s\n' "$execution" > "$result_file"
        break
        ;;
    esac

    sleep 10
  done

  if (( target_exit_code != 0 )); then
    printf 'Run Command did not succeed for %s.\n' "$target_name" >&2
    overall_exit_code=1
  fi
done < <(jq -c '.[]' <<< "$targets_json")

#==============================================================================
# RUN COMMAND RESULT
#==============================================================================

if (( overall_exit_code != 0 )); then
  exit "$overall_exit_code"
fi

printf 'oci_run_command=ready\n'