#!/usr/bin/env bash

#==============================================================================
# DOCKER COMPOSE PIPELINE OPERATIONS
#==============================================================================

#==============================================================================
# SHELL SAFETY
#==============================================================================

set -euo pipefail

#==============================================================================
# COMPOSE INPUTS
#==============================================================================

action="${1:-validate}"
compose_file="${COMPOSE_FILE:-compose.yaml}"
deploy_script="${DEPLOY_SCRIPT:-}"

#==============================================================================
# COMPOSE ACTION ROUTING
#==============================================================================

case "$action" in
  validate)
    docker compose --file "$compose_file" config --quiet
    ;;
  dry-run)
    docker compose --file "$compose_file" config
    if [[ -n "$deploy_script" ]]; then
      bash "$deploy_script" dry-run
    fi
    ;;
  deploy)
    if [[ -z "$deploy_script" ]]; then
      printf 'DEPLOY_SCRIPT is required for deployment.\n' >&2
      exit 1
    fi
    bash "$deploy_script" deploy
    ;;
  *)
    printf 'Usage: %s validate|dry-run|deploy\n' "$0" >&2
    exit 2
    ;;
esac

#==============================================================================
# COMPOSE RESULT
#==============================================================================

printf 'compose_%s=ready\n' "${action//-/_}"