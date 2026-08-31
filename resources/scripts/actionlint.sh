#!/usr/bin/env bash

#==============================================================================
# GITHUB WORKFLOW VALIDATION
#==============================================================================

#==============================================================================
# SHELL SAFETY
#==============================================================================

set -euo pipefail

#==============================================================================
# ACTIONLINT EXECUTION
#==============================================================================

script_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
actionlint_image="${ACTIONLINT_IMAGE:-rhysd/actionlint:1.7.7}"
"$script_directory/tool-container.sh" "$actionlint_image"

printf 'workflow_validation=ready\n'