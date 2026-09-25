#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE_NAME="shellcheck-legibility:e2e"

main() {
  local machine target
  machine="$(docker info --format '{{.Architecture}}')"
  case "$machine" in
    aarch64 | arm64) target=linux-arm64 ;;
    x86_64 | amd64) target=linux-amd64 ;;
    *)
      printf 'unsupported Docker architecture: %s\n' "$machine" >&2
      return 1
      ;;
  esac
  mkdir -p "$ROOT_DIR/.build/e2e"
  "$ROOT_DIR/scripts/package-release" 0.2.1 "$target" "$ROOT_DIR/.build/e2e/release.tar.gz" || return
  tar -xzf "$ROOT_DIR/.build/e2e/release.tar.gz" -C "$ROOT_DIR/.build/e2e" || return
  docker build --tag "$IMAGE_NAME" --file "$ROOT_DIR/tests/e2e/Dockerfile" "$ROOT_DIR"
  docker run --rm "$IMAGE_NAME"
}

main "$@"
