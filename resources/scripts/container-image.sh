#!/usr/bin/env bash

#==============================================================================
# SECURE CONTAINER IMAGE OPERATIONS
#==============================================================================

set -euo pipefail

#==============================================================================
# IMAGE INPUTS
#==============================================================================

action="${1:-validate}"
image_repository="${CONTAINER_IMAGE_REPOSITORY:?CONTAINER_IMAGE_REPOSITORY is required}"
image_tag="${CONTAINER_IMAGE_TAG:?CONTAINER_IMAGE_TAG is required}"
platforms="${CONTAINER_IMAGE_PLATFORMS:-linux/amd64,linux/arm64}"
trivy_image="${TRIVY_IMAGE:-aquasec/trivy:0.74.0@sha256:62b1e65e8869bc4b4c6aa4fa2b21595256c7c2f6018a9d9ad61caf87187c1969}"
scan_image="${image_repository}:${image_tag}-scan"
published_image="${image_repository}:${image_tag}"
output_directory="${CONTAINER_OUTPUT_DIRECTORY:-build}"
build_target="${CONTAINER_BUILD_TARGET:-}"

#==============================================================================
# INPUT VALIDATION
#==============================================================================

if [[ ! "$image_repository" =~ ^[a-z0-9.-]+(/[a-z0-9._-]+)+$ ]] || \
  [[ ! "$image_tag" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || \
  [[ ! "$platforms" =~ ^linux/(amd64|arm64)(,linux/(amd64|arm64))?$ ]]; then
  printf 'Invalid container image inputs.\n' >&2
  exit 2
fi

mkdir -p "$output_directory"

build_arguments=(--pull)
if [[ -n "$build_target" ]]; then
  if [[ ! "$build_target" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
    printf 'Invalid container build target.\n' >&2
    exit 2
  fi
  build_arguments+=(--target "$build_target")
fi

#==============================================================================
# IMAGE LIFECYCLE
#==============================================================================

case "$action" in
  validate)
    docker buildx version >/dev/null
    ;;
  build)
    docker build "${build_arguments[@]}" --tag "$scan_image" .
    ;;
  scan)
    jenkins_container_id="${JENKINS_CONTAINER_ID:-${HOSTNAME:-}}"
    docker_socket_gid=$(stat --format '%g' /var/run/docker.sock)
    docker run --rm --user "$(id -u):$(id -g)" \
      --group-add "$docker_socket_gid" \
      --volumes-from "$jenkins_container_id" \
      --volume /var/run/docker.sock:/var/run/docker.sock \
      --workdir "$PWD" \
      --env TRIVY_CACHE_DIR=/tmp/trivy-cache \
      "$trivy_image" image --exit-code 1 --ignore-unfixed \
      --scanners vuln --severity HIGH,CRITICAL "$scan_image"
    docker run --rm --user "$(id -u):$(id -g)" \
      --group-add "$docker_socket_gid" \
      --volumes-from "$jenkins_container_id" \
      --volume /var/run/docker.sock:/var/run/docker.sock \
      --workdir "$PWD" \
      --env TRIVY_CACHE_DIR=/tmp/trivy-cache \
      "$trivy_image" image --format cyclonedx \
      --output "$output_directory/sbom.cdx.json" "$scan_image"
    ;;
  publish)
    builder_name="jenkins-${image_tag//[^A-Za-z0-9_.-]/-}-$$"
    docker buildx create --name "$builder_name" --driver docker-container >/dev/null
    cleanup_builder() {
      docker buildx rm --force "$builder_name" >/dev/null 2>&1 || true
    }
    trap cleanup_builder EXIT
    docker buildx inspect --builder "$builder_name" --bootstrap >/dev/null
    docker buildx build --builder "$builder_name" "${build_arguments[@]}" --platform "$platforms" \
      --tag "$published_image" --metadata-file "$output_directory/image-metadata.json" \
      --provenance=mode=max --sbom=true --push .
    jq -er '."containerimage.digest" | select(test("^sha256:[a-f0-9]{64}$"))' \
      "$output_directory/image-metadata.json" | tee "$output_directory/image-digest"
    ;;
  *)
    printf 'Unsupported container image action: %s\n' "$action" >&2
    exit 2
    ;;
esac

printf 'container_image_%s=ready\n' "$action"