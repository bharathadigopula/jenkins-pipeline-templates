#!/usr/bin/env bash

#==============================================================================
# OPT-IN VALIDATION WORKSPACE OWNERSHIP RECOVERY
#==============================================================================

set -euo pipefail
container_id="${JENKINS_CONTAINER_ID:-${HOSTNAME:-}}"
workspace_root="${WORKSPACE:?WORKSPACE is required}"
if [[ -z "$container_id" || "$workspace_root" != /home/jenkins/agent/workspace/* || "$PWD" != "$workspace_root" ]]; then
  printf 'Workspace recovery requires the current Jenkins agent workspace.\n' >&2
  exit 1
fi
agent_image=$(docker inspect --format '{{.Config.Image}}' "$container_id")
docker run --rm --user 0 --network none --volumes-from "$container_id" \
  --workdir "$workspace_root" --entrypoint /bin/sh "$agent_image" \
  -c 'chown -R -h "$1" .' sh "$(id -u):$(id -g)"
printf 'workspace_permissions=ready\n'