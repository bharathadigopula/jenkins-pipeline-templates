#!/usr/bin/env bash

#==============================================================================
# IMMUTABLE GITHUB RELEASE OPERATIONS
#==============================================================================

#==============================================================================
# SHELL SAFETY
#==============================================================================

set -euo pipefail

#==============================================================================
# RELEASE INPUTS
#==============================================================================

action="${1:-validate}"
release_tag="${RELEASE_TAG:-}"

#==============================================================================
# RELEASE TAG VALIDATION
#==============================================================================

if [[ ! "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'RELEASE_TAG must be a semantic version tag.\n' >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  printf 'Release workspace must be clean.\n' >&2
  exit 1
fi

if git rev-parse "$release_tag" >/dev/null 2>&1; then
  printf 'Release tag already exists: %s\n' "$release_tag" >&2
  exit 1
fi

#==============================================================================
# RELEASE VALIDATION RESULT
#==============================================================================

if [[ "$action" == "validate" ]]; then
  printf 'release_validation=ready\n'
  exit 0
fi

#==============================================================================
# RELEASE ACTION VALIDATION
#==============================================================================

if [[ "$action" != "create" ]]; then
  printf 'Usage: %s validate|create\n' "$0" >&2
  exit 2
fi

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"

#==============================================================================
# IMMUTABLE RELEASE CREATION
#==============================================================================

git tag --annotate "$release_tag" --message "Release $release_tag"
git push origin "$release_tag"
gh release create "$release_tag" --generate-notes --verify-tag
printf 'release_create=ready\n'