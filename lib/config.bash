# shellcheck shell=bash
# shellcheck disable=SC2034

CONFIG_PENDING_KEY=""
CONFIG_PENDING_VALUES=()
CONFIG_ASSIGNMENT_KEY=""
CONFIG_ASSIGNMENT_VALUE=""

load_config() {
  local path
  path="$(resolve_config_path)"
  [[ -z "$path" ]] && return
  read_config_file "$path"
}

resolve_config_path() {
  [[ -n "$CONFIG_PATH" ]] && printf '%s\n' "$CONFIG_PATH" && return
  search_config_upward
}

search_config_upward() {
  local dir
  dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    config_in_dir "$dir" && return
    dir="$(dirname "$dir")"
  done
}

config_in_dir() {
  local dir="${1:-}"
  print_existing "$dir/.shellcheck-legibilityrc" && return 0
  print_existing "$dir/.shellcheck-legibility.yml" && return 0
  print_existing "$dir/.shellcheck-legibility.yaml" && return 0
  print_existing "$dir/shellcheck-legibility.toml" && return 0
  print_existing "$dir/.shellcheck-legibility.toml" && return 0
  print_existing "$dir/pyproject.toml"
}

print_existing() {
  [[ -f "${1:-}" ]] || return 1
  printf '%s\n' "${1:-}"
}

read_config_file() {
  local path="${1:-}"
  local in_section
  in_section="$(initial_config_section "$path")"
  read_config_lines "$path" "$in_section"
}

initial_config_section() {
  local path="${1:-}"
  [[ "$(basename "$path")" == "pyproject.toml" ]] && printf '%s\n' "0" && return
  printf '%s\n' "1"
}

read_config_lines() {
  local path="${1:-}"
  local in_section="${2:-}"
  local line
  reset_pending_config_values
  while IFS= read -r line || [[ -n "$line" ]]; do
    process_config_line "$line" "$in_section"
    in_section="$CONFIG_IN_SECTION"
  done < "$path"
  apply_pending_config_values
}

process_config_line() {
  local line="${1:-}"
  CONFIG_IN_SECTION="${2:-}"
  line="$(strip_config_comment "$line")"
  line="$(trim "$line")"
  [[ -z "$line" ]] && return
  append_pending_config_value "$line" && return
  apply_pending_config_values
  open_config_value_list "$line" && return
  process_config_content "$line"
}

strip_config_comment() {
  local line="${1:-}"
  local index
  index="$(config_comment_index "$line")"
  print_config_without_comment "$line" "$index"
}

print_config_without_comment() {
  local line="${1:-}"
  local index="${2:-}"
  [[ -z "$index" ]] && printf '%s\n' "$line" && return
  printf '%s\n' "${line:0:index}"
}

config_comment_index() {
  local line="${1:-}"
  local index char in_single="0" in_double="0" escaped="0"
  for ((index = 0; index < ${#line}; index++)); do
    char="${line:index:1}"
    [[ "$escaped" == "1" ]] && escaped="0" && continue
    [[ "$char" == "\\" && "$in_double" == "1" ]] && escaped="1" && continue
    [[ "$char" == "'" && "$in_double" == "0" ]] && in_single=$((1 - in_single)) && continue
    [[ "$char" == '"' && "$in_single" == "0" ]] && in_double=$((1 - in_double)) && continue
    [[ "$char" == "#" && "$in_single$in_double" == "00" ]] || continue
    printf '%s\n' "$index"
    return 0
  done
  return 1
}

append_pending_config_value() {
  local line="${1:-}"
  local value
  [[ -n "$CONFIG_PENDING_KEY" ]] || return 1
  [[ "$line" == "- "* ]] || return 1
  value="$(parse_yaml_scalar "${line#- }")"
  CONFIG_PENDING_VALUES+=("$value")
}

parse_yaml_scalar() {
  local value="${1:-}"
  local inner
  value="$(trim "$value")"
  case "$value" in
    \"*\") inner="${value:1:$((${#value} - 2))}"; decode_yaml_double_quoted "$inner" ;;
    \'*\') inner="${value:1:$((${#value} - 2))}"; printf '%s\n' "${inner//\'\'/\'}" ;;
    *) printf '%s\n' "$value" ;;
  esac
}

open_config_value_list() {
  local line="${1:-}"
  local key
  [[ "$CONFIG_IN_SECTION" == "1" ]] || return 1
  [[ "$line" == *: ]] || return 1
  key="$(trim "${line%:}")"
  config_array_key "$key" || return 1
  CONFIG_PENDING_KEY="$key"
  CONFIG_PENDING_VALUES=()
}

apply_pending_config_values() {
  [[ -n "$CONFIG_PENDING_KEY" ]] || return
  if [[ "${#CONFIG_PENDING_VALUES[@]}" -eq 0 ]]; then
    replace_config_array "$CONFIG_PENDING_KEY"
  else
    replace_config_array "$CONFIG_PENDING_KEY" "${CONFIG_PENDING_VALUES[@]}"
  fi
  reset_pending_config_values
}

replace_config_array() {
  local key="${1:-}"
  shift
  case "$key" in
    select) SELECT=("$@") ;;
    ignore) IGNORE=("$@") ;;
    exclude) EXCLUDE=("$@") ;;
    executable-entry-patterns) EXECUTABLE_ENTRY_PATTERNS=("$@") ;;
    direct-shell-entry-patterns) DIRECT_SHELL_ENTRY_PATTERNS=("$@") ;;
    executable-runtimes) EXECUTABLE_RUNTIMES=("$@") ;;
    comment-matchers) COMMENT_MATCHERS=("$@") ;;
    comment-prefix-identifiers) COMMENT_PREFIX_IDENTIFIERS=("$@") ;;
    comment-suffix-identifiers) COMMENT_SUFFIX_IDENTIFIERS=("$@") ;;
    automated-comment-identifiers) AUTOMATED_COMMENT_IDENTIFIERS=("$@") ;;
    *) return 1 ;;
  esac
}

reset_pending_config_values() {
  CONFIG_PENDING_KEY=""
  CONFIG_PENDING_VALUES=()
}

config_array_key() {
  case "${1:-}" in
    select|ignore|exclude) return 0 ;;
    executable-entry-patterns|direct-shell-entry-patterns|executable-runtimes) return 0 ;;
    comment-matchers|comment-prefix-identifiers|comment-suffix-identifiers) return 0 ;;
    automated-comment-identifiers) return 0 ;;
  esac
  return 1
}

process_config_content() {
  local line="${1:-}"
  [[ "$line" == \[*\] ]] || apply_config_content_assignment "$line"
  [[ "$line" == \[*\] ]] || return
  update_config_section "$line"
}

apply_config_content_assignment() {
  local line="${1:-}"
  [[ "$CONFIG_IN_SECTION" == "1" ]] && apply_config_assignment "$line"
}

update_config_section() {
  CONFIG_IN_SECTION="0"
  [[ "${1:-}" == "[tool.shellcheck-legibility]" ]] && CONFIG_IN_SECTION="1"
}

apply_config_assignment() {
  local line="${1:-}"
  parse_config_assignment "$line" || return
  apply_config_value "$CONFIG_ASSIGNMENT_KEY" "$CONFIG_ASSIGNMENT_VALUE"
}

parse_config_assignment() {
  local line="${1:-}"
  parse_equals_config_assignment "$line" && return
  parse_colon_config_assignment "$line"
}

parse_equals_config_assignment() {
  local line="${1:-}"
  local equals_pattern='^([A-Za-z0-9-]+)[[:space:]]*=[[:space:]]*(.*)$'
  [[ "$line" =~ $equals_pattern ]] || return 1
  CONFIG_ASSIGNMENT_KEY="${BASH_REMATCH[1]}"
  CONFIG_ASSIGNMENT_VALUE="${BASH_REMATCH[2]}"
}

parse_colon_config_assignment() {
  local line="${1:-}"
  local colon_pattern='^([A-Za-z0-9-]+)[[:space:]]*:[[:space:]]*(.*)$'
  [[ "$line" =~ $colon_pattern ]] || return 1
  CONFIG_ASSIGNMENT_KEY="${BASH_REMATCH[1]}"
  CONFIG_ASSIGNMENT_VALUE="${BASH_REMATCH[2]}"
}

apply_config_value() {
  local key="${1:-}"
  local value="${2:-}"
  apply_core_config_value "$key" "$value" && return
  apply_shell_config_value "$key" "$value" && return
  apply_comment_config_value "$key" "$value"
}

apply_core_config_value() {
  local key="${1:-}"
  local value="${2:-}"
  case "$key" in
    select) reset_array_from_csv SELECT "$value" ;;
    ignore) reset_array_from_csv IGNORE "$value" ;;
    exclude) reset_array_from_csv EXCLUDE "$value" ;;
    max-expression-operators) MAX_EXPRESSION_OPERATORS="$(clean_scalar "$value")" ;;
    max-if-operators) MAX_CONDITION_OPERATORS="$(clean_scalar "$value")" ;;
    max-control-flow-depth) MAX_CONTROL_FLOW_DEPTH="$(clean_scalar "$value")" ;;
    max-function-lines) MAX_FUNCTION_LINES="$(clean_scalar "$value")" ;;
    min-case-chain-length) MIN_CASE_CHAIN_LENGTH="$(clean_scalar "$value")" ;;
    min-object-lookup-chain-length) MIN_OBJECT_LOOKUP_CHAIN_LENGTH="$(clean_scalar "$value")" ;;
    min-dirname-match-depth) MIN_DIRNAME_MATCH_DEPTH="$(clean_scalar "$value")" ;;
    *) return 1 ;;
  esac
}

apply_shell_config_value() {
  local key="${1:-}"
  local value="${2:-}"
  case "$key" in
    executable-entry-patterns) reset_array_from_csv EXECUTABLE_ENTRY_PATTERNS "$value" ;;
    direct-shell-entry-patterns) reset_array_from_csv DIRECT_SHELL_ENTRY_PATTERNS "$value" ;;
    executable-runtimes) reset_array_from_csv EXECUTABLE_RUNTIMES "$value" ;;
    *) return 1 ;;
  esac
}

apply_comment_config_value() {
  local key="${1:-}"
  local value="${2:-}"
  case "$key" in
    comment-matchers) reset_array_from_csv COMMENT_MATCHERS "$value" ;;
    comment-prefix-identifiers) reset_array_from_csv COMMENT_PREFIX_IDENTIFIERS "$value" ;;
    comment-suffix-identifiers) reset_array_from_csv COMMENT_SUFFIX_IDENTIFIERS "$value" ;;
    automated-comment-identifiers) reset_array_from_csv AUTOMATED_COMMENT_IDENTIFIERS "$value" ;;
    *) return 1 ;;
  esac
}

reset_array_from_csv() {
  local array_name="${1:-}"
  local value="${2:-}"
  csv_to_array "$value"
  if [[ "${#PARSED_LIST[@]}" -eq 0 ]]; then
    case "$array_name" in
      SELECT) SELECT=() ;;
      IGNORE) IGNORE=() ;;
      EXCLUDE) EXCLUDE=() ;;
      EXECUTABLE_ENTRY_PATTERNS) EXECUTABLE_ENTRY_PATTERNS=() ;;
      DIRECT_SHELL_ENTRY_PATTERNS) DIRECT_SHELL_ENTRY_PATTERNS=() ;;
      EXECUTABLE_RUNTIMES) EXECUTABLE_RUNTIMES=() ;;
      COMMENT_MATCHERS) COMMENT_MATCHERS=() ;;
      COMMENT_PREFIX_IDENTIFIERS) COMMENT_PREFIX_IDENTIFIERS=() ;;
      COMMENT_SUFFIX_IDENTIFIERS) COMMENT_SUFFIX_IDENTIFIERS=() ;;
      AUTOMATED_COMMENT_IDENTIFIERS) AUTOMATED_COMMENT_IDENTIFIERS=() ;;
      *) return 1 ;;
    esac
    return
  fi
  case "$array_name" in
    SELECT) SELECT=("${PARSED_LIST[@]}") ;;
    IGNORE) IGNORE=("${PARSED_LIST[@]}") ;;
    EXCLUDE) EXCLUDE=("${PARSED_LIST[@]}") ;;
    EXECUTABLE_ENTRY_PATTERNS) EXECUTABLE_ENTRY_PATTERNS=("${PARSED_LIST[@]}") ;;
    DIRECT_SHELL_ENTRY_PATTERNS) DIRECT_SHELL_ENTRY_PATTERNS=("${PARSED_LIST[@]}") ;;
    EXECUTABLE_RUNTIMES) EXECUTABLE_RUNTIMES=("${PARSED_LIST[@]}") ;;
    COMMENT_MATCHERS) COMMENT_MATCHERS=("${PARSED_LIST[@]}") ;;
    COMMENT_PREFIX_IDENTIFIERS) COMMENT_PREFIX_IDENTIFIERS=("${PARSED_LIST[@]}") ;;
    COMMENT_SUFFIX_IDENTIFIERS) COMMENT_SUFFIX_IDENTIFIERS=("${PARSED_LIST[@]}") ;;
    AUTOMATED_COMMENT_IDENTIFIERS) AUTOMATED_COMMENT_IDENTIFIERS=("${PARSED_LIST[@]}") ;;
    *) return 1 ;;
  esac
}
