#!/usr/bin/env bash

set -u
ROOT_DIR="${1:?}"
OUTPUT_DIR="${2:?}"

initialize_reference() {
  # shellcheck source=rules.bash
  source <(sed '/^ROOT_DIR=/d; /^main "\$@"$/d' "$ROOT_DIR/tests/unit/rules.bash")
  source "$ROOT_DIR/lib/output.bash"
  eval "$(declare -f scan_line | sed '1s/scan_line/reference_scan_line/')"
  eval "$(declare -f capture_line | sed '1s/capture_line/scan_line/')"
  wrap_comment_checks
}

wrap_comment_checks() {
  local check
  for check in check_no_unmatched_comments check_no_automated_comment_attribution check_no_stacked_comments; do
    eval "$(declare -f "$check" | sed "1s/$check/reference_$check/")"
    eval "$check() { remember_line \"\$@\"; reference_$check \"\$@\"; }"
  done
}

capture_line() {
  remember_line "$@"
  reference_scan_line "$@"
}

remember_line() {
  [[ "$#" -ge 3 ]] || return 0
  local number="${2:?}"
  while [[ "${#FIXTURE_LINES[@]}" -lt "$number" ]]; do
    FIXTURE_LINES+=("")
  done
  FIXTURE_LINES[$((number - 1))]="${3:-}"
}

write_array() {
  local key="${1:?}" value escaped
  shift
  printf '"%s":[' "$key"
  local separator=""
  for value in "$@"; do
    json_escape_into escaped "$value"
    printf '%s"%s"' "$separator" "$escaped"
    separator=,
  done
  printf '],\n'
}

write_config() {
  printf '{\n'
  write_array select "${SELECT[@]}"
  write_array ignore "${IGNORE[@]}"
  write_array comment-matchers "${COMMENT_MATCHERS[@]}"
  write_array comment-prefix-identifiers "${COMMENT_PREFIX_IDENTIFIERS[@]}"
  write_array comment-suffix-identifiers "${COMMENT_SUFFIX_IDENTIFIERS[@]}"
  write_array automated-comment-identifiers "${AUTOMATED_COMMENT_IDENTIFIERS[@]}"
  printf '"max-expression-operators":%s,\n' "$MAX_EXPRESSION_OPERATORS"
  printf '"max-if-operators":%s,\n' "$MAX_CONDITION_OPERATORS"
  printf '"max-control-flow-depth":%s,\n' "$MAX_CONTROL_FLOW_DEPTH"
  printf '"max-function-lines":%s\n}\n' "$MAX_FUNCTION_LINES"
}

export_fixture() {
  local name="${1:?}"
  FIXTURE_LINES=()
  "$name"
  [[ "${#FIXTURE_LINES[@]}" -gt 0 ]] || return 0
  mkdir -p "$OUTPUT_DIR/$name"
  printf '%s\n' "${FIXTURE_LINES[@]}" > "$OUTPUT_DIR/$name/source.sh"
  write_config > "$OUTPUT_DIR/$name/config.json"
  write_json_diagnostics > "$OUTPUT_DIR/$name/expected.json"
}

export_fixtures() {
  initialize_reference
  shift 2
  local test_name
  for test_name in "$@"; do
    (export_fixture "$test_name")
  done
}

export_fixtures "$@"
