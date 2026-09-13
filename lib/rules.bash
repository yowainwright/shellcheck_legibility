rule_name() {
  case "${1:-}" in
    LEG001) printf '%s\n' "max-expression-operators" ;;
    LEG002) printf '%s\n' "hoist-if-operators" ;;
    LEG003) printf '%s\n' "max-control-flow-depth" ;;
    LEG005) printf '%s\n' "no-quadratic-patterns" ;;
    LEG006) printf '%s\n' "no-redundant-boolean-logic" ;;
    LEG007) printf '%s\n' "prefer-positive-condition-names" ;;
    LEG008) printf '%s\n' "no-trivial-wrapper-functions" ;;
    LEG009) printf '%s\n' "prefer-early-return" ;;
    LEG010) printf '%s\n' "prefer-guard-clauses" ;;
    *) shell_rule_name "${1:-}" ;;
  esac
}

shell_rule_name() {
  case "${1:-}" in
    LEG016) printf '%s\n' "require-executable-shebang" ;;
    LEG017) printf '%s\n' "no-direct-shell-bin-smoke" ;;
    LEG024) printf '%s\n' "prefer-object-lookup" ;;
    LEG025) printf '%s\n' "require-filename-matches-dirname" ;;
    LEG026) printf '%s\n' "no-mixed-filename-casing" ;;
    LEG034) printf '%s\n' "prefer-case-over-long-if-chain" ;;
    LEG035) printf '%s\n' "no-bool-literal-args" ;;
    LEG038) printf '%s\n' "max-function-lines" ;;
    LEG039) printf '%s\n' "prefer-functions" ;;
    LEG040) printf '%s\n' "use-defaults-in-functions" ;;
    LEG041) printf '%s\n' "no-unmatched-comments" ;;
    LEG042) printf '%s\n' "no-automated-comment-attribution" ;;
    LEG043) printf '%s\n' "no-stacked-comments" ;;
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
    LEG041|LEG042|LEG043) return 0 ;;
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
  local name
  name="$(rule_name "$code")"
  [[ "$selector" == "$code" || "$selector" == "$name" ]]
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
  local name
  name="$(rule_name "$code")"
  [[ "$selector" == "all" ]] && return 0
  [[ "$selector" == "LEG" ]] && return 0
  [[ "$selector" == "$code" || "$selector" == "$name" ]]
}

line_ignores_code() {
  local line="${1:-}"
  local code="${2:-}"
  [[ "$line" != *noqa* ]] && return 1
  [[ "$line" == *"$code"* || "$line" == *"LEG"* ]]
}
