#!/usr/bin/env bash

set -u -o pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGED_HOOK_TEST_DIR=""

test_staged_hook_uses_index_content() {
  local file output
  STAGED_HOOK_TEST_DIR="$(mktemp -d "$ROOT_DIR/.staged-hook-test.XXXXXX")"
  trap cleanup_staged_hook_test EXIT
  setup_staged_hook_fixture "$STAGED_HOOK_TEST_DIR"
  file=$'nested/odd\npath[1].sh'
  prepare_staged_hook_file "$STAGED_HOOK_TEST_DIR" "$file"
  output="$(env -i PATH="$PATH" "$STAGED_HOOK_TEST_DIR/scripts/setup/check-staged.sh")"
  assert_equal "staged contents" "$output"
  cleanup_staged_hook_test
  trap - EXIT
}

test_staged_hook_uses_index_config() {
  local output
  STAGED_HOOK_TEST_DIR="$(mktemp -d "$ROOT_DIR/.staged-hook-test.XXXXXX")"
  trap cleanup_staged_hook_test EXIT
  setup_staged_hook_fixture "$STAGED_HOOK_TEST_DIR"
  prepare_staged_hook_config_source "$STAGED_HOOK_TEST_DIR"
  output="$(env -i PATH="$PATH" TEST_LINTER_BIN="$ROOT_DIR/bin/shellcheck-legibility" "$STAGED_HOOK_TEST_DIR/scripts/setup/check-staged.sh" 2>&1)" || fail "fallback config should disable LEG041: $output"
  [[ "$output" != *"LEG041"* ]] || fail "fallback config unexpectedly enabled LEG041: $output"
  stage_staged_hook_config "$STAGED_HOOK_TEST_DIR"
  if output="$(env -i PATH="$PATH" TEST_LINTER_BIN="$ROOT_DIR/bin/shellcheck-legibility" "$STAGED_HOOK_TEST_DIR/scripts/setup/check-staged.sh" 2>&1)"; then
    fail "expected staged config to report LEG041"
  fi
  [[ "$output" == *"LEG041"* ]] || fail "expected staged config to enable LEG041: $output"
  cleanup_staged_hook_test
  trap - EXIT
}

setup_staged_hook_fixture() {
  local dir="${1:-}"
  mkdir -p "$dir/scripts/setup" "$dir/bin"
  cp "$ROOT_DIR/scripts/setup/check-staged.sh" "$dir/scripts/setup/check-staged.sh"
  write_staged_hook_linter "$dir/bin/shellcheck-legibility"
  chmod +x "$dir/bin/shellcheck-legibility"
  isolated_test_git -C "$dir" init -q
  isolated_test_git -C "$dir" config user.name "Unit Test"
  isolated_test_git -C "$dir" config user.email "unit-test@example.invalid"
}

isolated_test_git() {
  env -i PATH="$PATH" git "$@"
}

write_staged_hook_linter() {
  local path="${1:-}"
  cat > "$path" << 'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${TEST_LINTER_BIN:-}" ]]; then
  exec "$TEST_LINTER_BIN" "$@"
fi
[[ "${1:-}" == "check" ]]
shift
for file in "$@"; do
  cat "$file"
done
STUB
}

prepare_staged_hook_file() {
  local dir="${1:-}" file="${2:-}"
  mkdir -p "$(dirname "$dir/$file")"
  printf '%s\n' "staged contents" > "$dir/$file"
  isolated_test_git -C "$dir" add -- "$file"
  printf '%s\n' "unstaged contents" > "$dir/$file"
}

prepare_staged_hook_config_source() {
  local dir="${1:-}"
  printf '%s\n' 'select: [LEG001]' > "$dir/.shellcheck-legibility.yml"
  printf '%s\n' '#!/usr/bin/env bash' '# ordinary comment' 'printf ok' > "$dir/config-check.sh"
  isolated_test_git -C "$dir" add -- config-check.sh
}

stage_staged_hook_config() {
  local dir="${1:-}"
  printf '%s\n' 'select: [LEG041]' > "$dir/.shellcheck-legibility.yml"
  isolated_test_git -C "$dir" add -- .shellcheck-legibility.yml
  printf '%s\n' 'select: [LEG001]' > "$dir/.shellcheck-legibility.yml"
}

cleanup_staged_hook_test() {
  [[ -z "$STAGED_HOOK_TEST_DIR" ]] || rm -rf -- "$STAGED_HOOK_TEST_DIR"
  STAGED_HOOK_TEST_DIR=""
}

assert_equal() {
  local expected="${1:-}"
  local actual="${2:-}"
  [[ "$actual" == "$expected" ]] && return
  printf 'expected %s, got %s\n' "$expected" "$actual" >&2
  exit 1
}

fail() {
  printf '%s\n' "${1:-}" >&2
  exit 1
}

main() {
  test_staged_hook_uses_index_content
  test_staged_hook_uses_index_config
  printf "staged checks ok\n"
}

main "$@"
