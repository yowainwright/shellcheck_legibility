#!/usr/bin/env bash

set -u -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR=""
TEST_LINTER="$ROOT_DIR/bin/shellcheck-legibility"
TEST_FILE=""
RUN_OUTPUT=""
RUN_STATUS=0

fail() {
  printf '%s\n' "${1:-}" >&2
  exit 1
}

cleanup() {
  [[ -n "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

run_linter() {
  RUN_STATUS=0
  RUN_OUTPUT="$(SHELLCHECK_LEGIBILITY_CACHE_DIR="$TEST_DIR/cache" "$TEST_LINTER" \
    check "$TEST_FILE" --config "$TEST_DIR/config.yml" --output-format json "$@")" || RUN_STATUS="$?"
  [[ "$RUN_STATUS" -le 1 ]] || fail "linter failed: $RUN_STATUS"
}

assert_status() {
  [[ "$RUN_STATUS" == "${1:-}" ]] || fail "expected status ${1:-}, got $RUN_STATUS: $RUN_OUTPUT"
}

test_cached_findings() {
  local expected entries
  run_linter --no-cache
  assert_status 1
  expected="$RUN_OUTPUT"
  run_linter
  [[ "$RUN_OUTPUT" == "$expected" ]] || fail "cold cache changed findings"
  entries=("$TEST_DIR/cache"/*)
  [[ "${#entries[@]}" -eq 1 ]] || fail "expected one cache entry"
  touch -t 200001010000 "${entries[0]}"
  touch "$TEST_DIR/marker"
  run_linter
  assert_status 1
  [[ "$RUN_OUTPUT" == "$expected" ]] || fail "warm cache changed findings"
  [[ "${entries[0]}" -ot "$TEST_DIR/marker" ]] || fail "cache hit rescanned the file"
}

test_output_and_exit_options() {
  local expected
  run_linter --no-cache --output-format text
  expected="$RUN_OUTPUT"
  run_linter --output-format text --exit-zero
  assert_status 0
  [[ "$RUN_OUTPUT" == "$expected" ]] || fail "cached text output changed"
}

test_corrupt_cache() {
  local entry expected
  run_linter --no-cache
  expected="$RUN_OUTPUT"
  for entry in "$TEST_DIR/cache"/*; do
    printf 'cache-v1\0end' > "$entry"
  done
  run_linter
  assert_status 1
  [[ "$RUN_OUTPUT" == "$expected" ]] || fail "truncated cache hid findings"
}

test_content_invalidation() {
  touch -r "$TEST_FILE" "$TEST_DIR/timestamp"
  printf '%s\n' 'run() { create_user name; }' > "$TEST_FILE"
  touch -r "$TEST_DIR/timestamp" "$TEST_FILE"
  run_linter
  assert_status 0
  run_linter
  assert_status 0
  printf '%s\n' 'run() { create_user true; }' > "$TEST_FILE"
  touch -r "$TEST_DIR/timestamp" "$TEST_FILE"
  run_linter
  assert_status 1
}

test_config_invalidation() {
  printf '%s\n' 'select: [LEG038]' 'max-function-lines: 20' > "$TEST_DIR/config.yml"
  run_linter
  assert_status 0
  printf '%s\n' 'select: [LEG038]' 'max-function-lines: 0' > "$TEST_DIR/config.yml"
  run_linter
  assert_status 1
  run_linter --select LEG035 --ignore LEG035
  assert_status 0
  run_linter --select LEG035
  assert_status 1
}

test_unavailable_cache() {
  local expected
  run_linter --no-cache
  expected="$RUN_OUTPUT"
  mv "$TEST_DIR/cache" "$TEST_DIR/saved-cache"
  printf 'not a directory\n' > "$TEST_DIR/cache"
  run_linter
  assert_status 1
  [[ "$RUN_OUTPUT" == "$expected" ]] || fail "unavailable cache changed findings"
  rm "$TEST_DIR/cache"
  mv "$TEST_DIR/saved-cache" "$TEST_DIR/cache"
}

test_packaged_cache() {
  [[ "${SKIP_PACKAGE_TEST:-}" == "1" ]] && return
  local target
  target="$(go env GOOS)-$(go env GOARCH)"
  "$BASH" "$ROOT_DIR/scripts/package-release" 0.2.5 "$target" "$TEST_DIR/bundle.tar.gz"
  tar -xzf "$TEST_DIR/bundle.tar.gz" -C "$TEST_DIR"
  TEST_LINTER="$TEST_DIR/shellcheck-legibility"
  run_linter
  assert_status 1
  local expected="$RUN_OUTPUT" before after
  before=("$TEST_DIR/cache"/*)
  run_linter
  [[ "$RUN_OUTPUT" == "$expected" ]] || fail "packaged cache changed findings"
  "$BASH" "$ROOT_DIR/scripts/package-release" 0.2.6 "$target" "$TEST_DIR/bundle.tar.gz"
  tar -xzf "$TEST_DIR/bundle.tar.gz" -C "$TEST_DIR"
  run_linter
  after=("$TEST_DIR/cache"/*)
  [[ "${#after[@]}" -eq "$((${#before[@]} + 1))" ]] || fail "engine change reused stale cache"
}

test_file_diagnostics_do_not_inherit_directives() {
  local original="$TEST_FILE" expected
  TEST_FILE="$TEST_DIR/first.sh"
  printf '%s\n' '#!/bin/bash' 'run() { :; } # noqa: LEG016' > "$TEST_FILE"
  printf '%s\n' 'run() { :; }' > "$TEST_DIR/second.sh"
  printf '%s\n' 'select: [LEG016]' 'executable-entry-patterns: ["*.sh"]' > "$TEST_DIR/config.yml"
  run_linter --no-cache "$TEST_DIR/second.sh"
  assert_status 1
  expected="$RUN_OUTPUT"
  run_linter "$TEST_DIR/second.sh"
  run_linter "$TEST_DIR/second.sh"
  assert_status 1
  [[ "$RUN_OUTPUT" == "$expected" ]] || fail "cache changed diagnostics across files"
  TEST_FILE="$original"
  printf '%s\n' 'select: [LEG035]' > "$TEST_DIR/config.yml"
}

main() {
  TEST_DIR="$(mktemp -d "$ROOT_DIR/.cache-test.XXXXXX")"
  trap cleanup EXIT
  TEST_FILE="$TEST_DIR/odd"$'\n'"path[1]\".sh"
  printf '%s\n' 'select: [LEG035]' > "$TEST_DIR/config.yml"
  printf '%s\n' 'run() { create_user true; }' > "$TEST_FILE"
  test_cached_findings
  test_output_and_exit_options
  test_corrupt_cache
  test_content_invalidation
  test_config_invalidation
  test_unavailable_cache
  test_file_diagnostics_do_not_inherit_directives
  test_packaged_cache
  printf '%s\n' 'cache ok'
}

main "$@"
