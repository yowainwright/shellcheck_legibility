#!/usr/bin/env bash

set -u

main() {
  assert_no_shellcheck
  assert_version
  assert_text_diagnostic
  assert_json_diagnostic
  assert_no_false_positives
  assert_boolean_argument_reported
  assert_incomplete_shell_feedback
  printf '%s\n' "ok"
}

assert_no_shellcheck() {
  command -v shellcheck > /dev/null 2>&1 && fail "shellcheck should not be installed"
}

assert_version() {
  [[ "$(shellcheck-legibility --version)" == "0.2.1" ]] || fail "expected version 0.2.1"
}

assert_text_diagnostic() {
  write_fixture
  run_linter "text"
  [[ "$STATUS" -eq 1 ]] || fail "expected text run to exit 1"
  [[ "$OUTPUT" == *"LEG002"* ]] || fail "expected LEG002 in text output"
}

assert_json_diagnostic() {
  write_fixture
  run_linter "json"
  [[ "$STATUS" -eq 1 ]] || fail "expected json run to exit 1"
  [[ "$OUTPUT" == *'"code":"LEG002"'* ]] || fail "expected LEG002 in json output"
}

write_fixture() {
  local condition
  mkdir -p sample/scripts
  condition='if [[ -n "$USER" && -n "$HOME" ]]; then'
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' "$condition"
    printf '%s\n' '  printf "%s\n" "$USER"'
    printf '%s\n' 'fi'
  } > sample/scripts/example.sh
}

run_linter() {
  local format="${1:-}"
  set +e
  OUTPUT="$(shellcheck-legibility check sample/scripts/example.sh --output-format "$format" 2>&1)"
  STATUS="$?"
  set -u
}

fail() {
  printf '%s\n' "${1:-}" >&2
  exit 1
}

assert_no_false_positives() {
  mkdir -p sample/scripts
  printf '%s\n' '#!/usr/bin/env bash' 'run() {' \
    'if ready; then' 'return 0' 'fi' \
    "printf '%s\\n' 'true false a|b|c|d|e|f'" \
    'work || true' '}' 'run' > sample/scripts/index.sh
  OUTPUT="$(shellcheck-legibility check sample/scripts/index.sh --output-format json)"
  STATUS="$?"
  [[ "$STATUS" -eq 0 ]] || fail "expected quoted data and guard clauses to pass: $OUTPUT"
  local normalized="${OUTPUT//[[:space:]]/}"
  [[ "$normalized" == "[]" ]] || fail "expected no diagnostics: $OUTPUT"
}

assert_boolean_argument_reported() {
  printf '%s\n' '#!/usr/bin/env bash' 'run() { create_user true; }' 'run' > sample/scripts/boolean.sh
  OUTPUT="$(shellcheck-legibility check sample/scripts/boolean.sh --select LEG035 --output-format json)"
  STATUS="$?"
  [[ "$STATUS" -eq 1 ]] || fail "expected a boolean argument diagnostic"
  [[ "$OUTPUT" == *'"code":"LEG035"'* ]] || fail "expected LEG035 in JSON output"
}

assert_incomplete_shell_feedback() {
  printf '%s\n' 'run() { create_user true;' > sample/scripts/incomplete.sh
  OUTPUT="$(shellcheck-legibility check sample/scripts/incomplete.sh --select LEG035 --output-format json)"
  STATUS="$?"
  [[ "$STATUS" -eq 1 ]] || fail "expected feedback for incomplete shell syntax"
  [[ "$OUTPUT" == *'"code":"LEG035"'* ]] || fail "expected embedded Bash compatibility scanner"
}

main "$@"
