rule_name() {
  set_rule_name "${1:-}"
  printf '%s\n' "$RULE_NAME"
}

set_rule_name() {
  RULE_NAME=""
  case "${1:-}" in
    LEG001) RULE_NAME="max-expression-operators" ;;
    LEG002) RULE_NAME="hoist-if-operators" ;;
    LEG003) RULE_NAME="max-control-flow-depth" ;;
    LEG005) RULE_NAME="no-quadratic-patterns" ;;
    LEG006) RULE_NAME="no-redundant-boolean-logic" ;;
    LEG007) RULE_NAME="prefer-positive-condition-names" ;;
    LEG008) RULE_NAME="no-trivial-wrapper-functions" ;;
    LEG009) RULE_NAME="prefer-early-return" ;;
    LEG010) RULE_NAME="prefer-guard-clauses" ;;
    *) set_shell_rule_name "${1:-}" ;;
  esac
}

set_shell_rule_name() {
  case "${1:-}" in
    LEG016) RULE_NAME="require-executable-shebang" ;;
    LEG017) RULE_NAME="no-direct-shell-bin-smoke" ;;
    LEG024) RULE_NAME="prefer-object-lookup" ;;
    LEG025) RULE_NAME="require-filename-matches-dirname" ;;
    LEG026) RULE_NAME="no-mixed-filename-casing" ;;
    LEG034) RULE_NAME="prefer-case-over-long-if-chain" ;;
    LEG035) RULE_NAME="no-bool-literal-args" ;;
    LEG038) RULE_NAME="max-function-lines" ;;
    LEG039) RULE_NAME="prefer-functions" ;;
    LEG040) RULE_NAME="use-defaults-in-functions" ;;
    LEG041) RULE_NAME="no-unmatched-comments" ;;
    LEG042) RULE_NAME="no-automated-comment-attribution" ;;
    LEG043) RULE_NAME="no-stacked-comments" ;;
  esac
}

rule_enabled() {
  local code="${1:-}"
  [[ "${#SELECT[@]}" -gt 0 ]] || return 1
  selector_matches_any "$code" "${SELECT[@]}" || return 1
  comment_rule_selected "$code" || return 1
  if [[ "${#IGNORE[@]}" -gt 0 ]]; then
    selector_matches_any "$code" "${IGNORE[@]}" && return 1
  fi
  return 0
}

comment_rule_selected() {
  local code="${1:-}"
  comment_rule_code "$code" || return 0
  selector_explicitly_matches_any "$code" "${SELECT[@]}"
}

comment_rule_code() {
  case "${1:-}" in
    LEG041 | LEG042 | LEG043) return 0 ;;
  esac
  return 1
}

selector_explicitly_matches_any() {
  local code="${1:-}"
  local selector
  shift
  [[ "$#" -gt 0 ]] || return 1
  for selector in "$@"; do
    selector_explicitly_matches "$code" "$selector" && return 0
  done
  return 1
}

selector_explicitly_matches() {
  local code="${1:-}"
  local selector="${2:-}"
  [[ "$selector" == "$code" ]] && return 0
  set_rule_name "$code"
  [[ "$selector" == "$RULE_NAME" ]]
}

selector_matches_any() {
  local code="${1:-}"
  local selector
  shift
  [[ "$#" -gt 0 ]] || return 1
  for selector in "$@"; do
    selector_matches "$code" "$selector" && return 0
  done
  return 1
}

selector_matches() {
  local code="${1:-}"
  local selector="${2:-}"
  [[ "$selector" == "all" ]] && return 0
  [[ "$selector" == "LEG" ]] && return 0
  [[ "$selector" == "$code" ]] && return 0
  set_rule_name "$code"
  [[ "$selector" == "$RULE_NAME" ]]
}

line_ignores_code() {
  local line="${1:-}"
  local code="${2:-}"
  [[ "$line" != *noqa* ]] && return 1
  [[ "$line" == *"$code"* || "$line" == *"LEG"* ]]
}
