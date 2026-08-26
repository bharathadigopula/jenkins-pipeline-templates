#!/usr/bin/env bash

#==============================================================================
# SHELL PIPELINE VALIDATION
#==============================================================================

#==============================================================================
# SHELL SAFETY
#==============================================================================

set -euo pipefail

#==============================================================================
# VALIDATION INPUTS
#==============================================================================

search_path="${SHELL_SEARCH_PATH:-.}"
shellcheck_image="${SHELLCHECK_IMAGE:-koalaman/shellcheck:v0.10.0}"
script_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

#==============================================================================
# SHELL SCRIPT DISCOVERY
#==============================================================================

mapfile -d '' shell_files < <(find "$search_path" -type f -name '*.sh' -print0)

if (( ${#shell_files[@]} == 0 )); then
  printf 'No shell scripts found under %s.\n' "$search_path" >&2
  exit 1
fi

#==============================================================================
# SHELLCHECK EXECUTION
#==============================================================================

"$script_directory/tool-container.sh" "$shellcheck_image" "${shell_files[@]}"
printf 'shell_validation=ready\n'