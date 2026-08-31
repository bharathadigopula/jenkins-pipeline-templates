#!/usr/bin/env bash

#==============================================================================
# OCI RUN COMMAND INSTANCE PRINCIPAL TEST
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
# MOCK OCI CLI
#==============================================================================

cat > "$temporary_directory/bin/oci" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
command_line=${*//$'\n'/ }
printf '%s\n' "$command_line" >> "$OCI_TEST_CALLS"

case "$1 $2 $3" in
  'vault secret list')
    secret_name=''
    while (( $# > 0 )); do
      if [[ "$1" == '--name' ]]; then
        secret_name="$2"
        break
      fi
      shift
    done
    jq -cn --arg id "ocid1.vaultsecret.${secret_name}" '{data: [{id: $id}]}'
    ;;
  'secrets secret-bundle get')
    secret_id=''
    while (( $# > 0 )); do
      if [[ "$1" == '--secret-id' ]]; then
        secret_id="$2"
        break
      fi
      shift
    done
    secret_value="${secret_id##*.}-value"
    jq -cn --arg content "$(printf '%s' "$secret_value" | base64)" \
      '{data: {"secret-bundle-content": {content: $content}}}'
    ;;
  'instance-agent command create')
    while (( $# > 0 )); do
      if [[ "$1" == '--content' ]]; then
        jq -r '.source.text' <<< "$2" > "$OCI_TEST_COMMAND"
        break
      fi
      shift
    done
    jq -cn '{data: {id: "ocid1.instanceagentcommand.test"}}'
    ;;
  'instance-agent command-execution get')
    jq -cn '{data: {"lifecycle-state": "SUCCEEDED", content: {text: "jenkins_deploy=ready"}}}'
    ;;
  *)
    printf 'Unexpected OCI command: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$temporary_directory/bin/oci"

#==============================================================================
# TEST EXECUTION
#==============================================================================

cat > "$temporary_directory/bootstrap.sh" <<'EOF'
#!/usr/bin/env bash
printf 'bootstrap=ready\n'
EOF
chmod +x "$temporary_directory/bootstrap.sh"

export OCI_CLI_CONTAINER_READY=true
export OCI_RUN_COMMAND_ACTION=deploy
export OCI_RUN_COMMAND_AUTH_MODE=instance-principal
export OCI_RUN_COMMAND_COMPARTMENT_OCID=ocid1.compartment.oc1..test
export OCI_RUN_COMMAND_REGION=ap-hyderabad-1
export OCI_TEST_CALLS="$temporary_directory/oci-calls"
export OCI_TEST_COMMAND="$temporary_directory/dispatched-command"
export PATH="$temporary_directory/bin:$PATH"
export RUN_COMMAND_ADDITIONAL_VAULT_SECRET_NAME=additional
export RUN_COMMAND_REQUIRED_OUTPUT_MARKER=jenkins_deploy=ready
export RUN_COMMAND_RESULTS_DIRECTORY="$temporary_directory/results"
export RUN_COMMAND_SCRIPT_PATH="$temporary_directory/bootstrap.sh"
export RUN_COMMAND_TARGETS='[{"name":"platform","instance_id":"ocid1.instance.oc1.ap-hyderabad-1.test","arguments":["repository","v1.0.0"]}]'
export RUN_COMMAND_TERTIARY_VAULT_SECRET_NAME=tertiary
export RUN_COMMAND_TIMEOUT_SECONDS=30
export RUN_COMMAND_VAULT_SECRET_NAME=primary

bash "$repository_root/resources/scripts/oci-run-command.sh" >/dev/null

#==============================================================================
# TEST ASSERTIONS
#==============================================================================

expected_arguments="set -- 'deploy' 'repository' 'v1.0.0' 'primary-value' 'additional-value' 'tertiary-value'"
if ! grep -Fq "$expected_arguments" "$OCI_TEST_COMMAND"; then
  printf 'Vault secrets were not appended in the required order.\n' >&2
  exit 1
fi

#==============================================================================
# RAW ARGUMENT CONTRACT ASSERTION
#==============================================================================

export RUN_COMMAND_PREPEND_ACTION=false
bash "$repository_root/resources/scripts/oci-run-command.sh" >/dev/null
expected_raw_arguments="set -- 'repository' 'v1.0.0' 'primary-value' 'additional-value' 'tertiary-value'"
if ! grep -Fq "$expected_raw_arguments" "$OCI_TEST_COMMAND"; then
  printf 'Run Command prepended an action to a raw argument contract.\n' >&2
  exit 1
fi

unprotected_call=$(awk 'index($0, "--auth instance_principal") == 0 { print; exit }' "$OCI_TEST_CALLS")
if [[ -n "$unprotected_call" ]]; then
  printf 'OCI call did not use instance-principal authentication: %s\n' "$unprotected_call" >&2
  exit 1
fi

#==============================================================================
# DETACHED DISPATCH ASSERTIONS
#==============================================================================

cat > "$temporary_directory/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
command_line=${*//$'\n'/ }
printf '%s\n' "$command_line" > "$OCI_TEST_DOCKER_CALL"
printf 'detached-container-id\n'
EOF
chmod +x "$temporary_directory/bin/docker"

export HOSTNAME=jenkins-controller
export OCI_CLI_CONTAINER_READY=false
export OCI_TEST_DOCKER_CALL="$temporary_directory/docker-call"
export RUN_COMMAND_DETACHED=true

dispatch_output=$(bash "$repository_root/resources/scripts/oci-run-command.sh")
if [[ "$dispatch_output" != 'oci_run_command=dispatched' ]]; then
  printf 'Detached OCI Run Command did not report dispatch.\n' >&2
  exit 1
fi

if ! grep -Fq 'run --detach --rm' "$OCI_TEST_DOCKER_CALL" || \
  ! grep -Fq -- '--network host' "$OCI_TEST_DOCKER_CALL"; then
  printf 'Detached OCI Run Command did not use a disposable host-networked container.\n' >&2
  exit 1
fi

printf 'oci_run_command_test=ready\n'