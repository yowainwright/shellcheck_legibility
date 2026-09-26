#!/usr/bin/env bash

set -u -o pipefail

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
  prepare_bundle "$target" || return
  build_image || return
  docker run --rm "$IMAGE_NAME"
}

prepare_bundle() {
  local target="${1:?}"
  mkdir -p "$ROOT_DIR/.build/e2e"
  "$ROOT_DIR/scripts/package-release" 0.2.1 "$target" "$ROOT_DIR/.build/e2e/release.tar.gz" || return
  tar -xzf "$ROOT_DIR/.build/e2e/release.tar.gz" -C "$ROOT_DIR/.build/e2e" || return
  touch "$ROOT_DIR/.build/e2e/shellcheck-legibility"
}

build_image() {
  docker build --tag "$IMAGE_NAME" --file "$ROOT_DIR/tests/e2e/Dockerfile" "$ROOT_DIR" || return
  docker run --rm --entrypoint cat "$IMAGE_NAME" /usr/local/bin/shellcheck-legibility |
    cmp "$ROOT_DIR/.build/e2e/shellcheck-legibility" -
}

main "$@"
