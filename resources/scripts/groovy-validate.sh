#!/usr/bin/env bash

#==============================================================================
# GROOVY SOURCE VALIDATION
#==============================================================================

#==============================================================================
# SHELL SAFETY
#==============================================================================

set -euo pipefail

#==============================================================================
# GROOVY INPUTS
#==============================================================================

search_path="${GROOVY_SEARCH_PATH:?GROOVY_SEARCH_PATH is required}"
groovy_image="${GROOVY_IMAGE:-groovy:4.0.27-jdk21}"
script_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mapfile -d '' groovy_files < <(find "$search_path" -type f -name '*.groovy' -print0)

if (( ${#groovy_files[@]} == 0 )); then
  printf 'No Groovy files found under %s.\n' "$search_path" >&2
  exit 1
fi

#==============================================================================
# GROOVY COMPILATION
#==============================================================================

"$script_directory/tool-container.sh" "$groovy_image" groovyc -d /tmp/classes "${groovy_files[@]}"
printf 'groovy_validation=ready\n'