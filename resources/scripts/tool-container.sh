#!/usr/bin/env bash

#==============================================================================
# JENKINS TOOL CONTAINER EXECUTION
#==============================================================================

#==============================================================================
# SHELL SAFETY
#==============================================================================

set -euo pipefail

#==============================================================================
# TOOL INPUTS
#==============================================================================

tool_image="${1:?Tool image is required}"
shift
jenkins_container_id="${JENKINS_CONTAINER_ID:-${HOSTNAME:-}}"

#==============================================================================
# CONTAINER VALIDATION
#==============================================================================

if [[ -z "$jenkins_container_id" ]]; then
  printf 'JENKINS_CONTAINER_ID or HOSTNAME is required.\n' >&2
  exit 1
fi

#==============================================================================
# CLOUD ENVIRONMENT FORWARDING
#==============================================================================

docker_arguments=(
  --rm
  --user "$(id -u):$(id -g)"
  --volumes-from "$jenkins_container_id"
  --workdir "$PWD"
)

if [[ -n "${TOOL_CONTAINER_HOME:-}" ]]; then
  docker_arguments+=(--env "HOME=$TOOL_CONTAINER_HOME")
fi

while IFS='=' read -r variable_name _; do
  case "$variable_name" in
    ARM_*|AWS_*|CLOUDFLARE_*|OCI_*|TF_*)
      docker_arguments+=(--env "$variable_name")
      ;;
  esac
done < <(env)

#==============================================================================
# TOOL EXECUTION
#==============================================================================

exec docker run "${docker_arguments[@]}" "$tool_image" "$@"