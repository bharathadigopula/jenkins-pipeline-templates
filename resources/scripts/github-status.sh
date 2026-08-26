#!/usr/bin/env bash

#==============================================================================
# GITHUB COMMIT STATUS REPORTING
#==============================================================================

#==============================================================================
# SHELL SAFETY
#==============================================================================

set -euo pipefail

#==============================================================================
# STATUS INPUTS
#==============================================================================

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GIT_COMMIT:?GIT_COMMIT is required}"

state="${1:-${GITHUB_STATUS_STATE:-pending}}"
description="${2:-${GITHUB_STATUS_DESCRIPTION:-Jenkins pipeline status}}"
context="${GITHUB_STATUS_CONTEXT:-continuous-integration/jenkins}"
target_url="${BUILD_URL:-}"

#==============================================================================
# STATUS VALIDATION
#==============================================================================

if [[ "$state" != "error" && "$state" != "failure" && "$state" != "pending" && "$state" != "success" ]]; then
  printf 'Invalid GitHub commit status: %s\n' "$state" >&2
  exit 2
fi

#==============================================================================
# STATUS PAYLOAD
#==============================================================================

payload=$(jq -n \
  --arg state "$state" \
  --arg target_url "$target_url" \
  --arg description "$description" \
  --arg context "$context" \
  '{state: $state, target_url: $target_url, description: $description, context: $context}')

#==============================================================================
# STATUS API REQUEST
#==============================================================================

curl --fail --silent --show-error \
  --request POST \
  --header "Authorization: Bearer $GITHUB_TOKEN" \
  --header 'Accept: application/vnd.github+json' \
  --header 'X-GitHub-Api-Version: 2022-11-28' \
  --data "$payload" \
  "https://api.github.com/repos/$GITHUB_REPOSITORY/statuses/$GIT_COMMIT" >/dev/null

printf 'github_status=ready\n'