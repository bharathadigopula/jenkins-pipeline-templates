#!/usr/bin/env bash

#==============================================================================
# CONTAINER BUILD TARGET REGRESSIONS
#==============================================================================

set -euo pipefail
repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT
mkdir -p "$temporary_directory/bin"
export DOCKER_TEST_LOG="$temporary_directory/docker.log"
export CONTAINER_IMAGE_REPOSITORY=ghcr.io/example/application
export CONTAINER_IMAGE_TAG=sha-123456789abc
export CONTAINER_OUTPUT_DIRECTORY="$temporary_directory/build"
export PATH="$temporary_directory/bin:$PATH"

#==============================================================================
# ISOLATED DOCKER COMMAND CAPTURE
#==============================================================================

cat > "$temporary_directory/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >> "$DOCKER_TEST_LOG"
while (( $# > 0 )); do
  if [[ "$1" == '--metadata-file' ]]; then
    printf '{"containerimage.digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}\n' > "$2"
    break
  fi
  shift
done
MOCK
chmod +x "$temporary_directory/bin/docker"

#==============================================================================
# DEFAULT AND EXPLICIT TARGETS
#==============================================================================

CONTAINER_BUILD_TARGET='' bash "$repository_root/resources/scripts/container-image.sh" build >/dev/null
if grep -Fxq -- '--target' "$DOCKER_TEST_LOG"; then
  printf 'Default image build unexpectedly selected a target.\n' >&2
  exit 1
fi
for operation in build publish; do
  : > "$DOCKER_TEST_LOG"
  CONTAINER_BUILD_TARGET=migration bash "$repository_root/resources/scripts/container-image.sh" "$operation" >/dev/null
  grep -Fxq -- '--target' "$DOCKER_TEST_LOG"
  grep -Fxq -- 'migration' "$DOCKER_TEST_LOG"
done
if CONTAINER_BUILD_TARGET='migration --push' bash "$repository_root/resources/scripts/container-image.sh" build >/dev/null 2>&1; then
  printf 'Invalid build target was accepted.\n' >&2
  exit 1
fi
printf 'container_image_target_tests=passed\n'