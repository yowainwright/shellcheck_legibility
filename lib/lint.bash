CACHED_AUTOMATED_COMMENT_IDENTIFIERS=()
NORMALIZED_AUTOMATED_COMMENT_IDENTIFIERS=()
AUTOMATED_COMMENT_IDENTIFIER=""
COMMENT_RULE_STATE_READY="0"
COMMENT_RULES_ENABLED="0"
NO_UNMATCHED_COMMENTS_ENABLED="0"
NO_AUTOMATED_COMMENT_ATTRIBUTION_ENABLED="0"
NO_STACKED_COMMENTS_ENABLED="0"
COMMENT_PARSER_IN_SINGLE_QUOTE="0"
COMMENT_PARSER_IN_ANSI_C_QUOTE="0"
LAST_COMMENT_LINE="0"
HEREDOC_DELIMITERS=()
HEREDOC_TAB_STRIPPING=()
PENDING_HEREDOC_DELIMITERS=()
PENDING_HEREDOC_TAB_STRIPPING=()
PARSED_HEREDOC_OPERATOR_INDEX="0"
PARSED_HEREDOC_DELIMITER=""
PARSED_HEREDOC_TAB_STRIPPING="0"
PARSED_HEREDOC_TOKEN=""
SHELL_COMMENT_FOUND="0"
SHELL_COMMENT_INDEX="0"
SHELL_IN_SINGLE_QUOTE="0"
SHELL_IN_DOUBLE_QUOTE="0"
SHELL_IN_ANSI_C_QUOTE="0"
SHELL_PARENT_SINGLE_QUOTES=()
SHELL_PARENT_DOUBLE_QUOTES=()
SHELL_COMMAND_PAREN_DEPTHS=()
SHELL_CONTEXT_TYPES=()
SHELL_CASE_STATES=()
SHELL_SCAN_ESCAPED="0"

lint_files() {
  local file
  prepare_comment_rule_state
  [[ "${#FILES[@]}" -gt 0 ]] || return
  for file in "${FILES[@]}"; do
    lint_file "$file"
  done
}

lint_file() {
  local path="${1:-}"
  reset_scan_state "$path"
  check_file_rules "$path"
  scan_file_lines "$path"
}

reset_scan_state() {
  SCAN_PATH="${1:-}"
  SCAN_LINE_NUMBER="0"
  reset_structure_scan_state
  reset_function_scan_state
  reset_comment_syntax_state
}

reset_structure_scan_state() {
  CONTROL_FLOW_DEPTH="0"
  LOOP_DEPTH="0"
  IF_DEPTH="0"
  IF_THEN_EXIT=()
  IF_COMPARE_NAME=()
  IF_COMPARE_COUNT=()
  IF_COMPARE_REPORTED=()
}

reset_function_scan_state() {
  IN_FUNCTION="0"
  FUNCTION_START_LINE="0"
  PENDING_FUNCTION_DECLARATION="0"
  PENDING_FUNCTION_START_LINE="0"
  PREFER_FUNCTIONS_REPORTED="0"
  FUNCTION_NAMES=()
}

reset_comment_syntax_state() {
  HEREDOC_DELIMITERS=()
  HEREDOC_TAB_STRIPPING=()
  PENDING_HEREDOC_DELIMITERS=()
  PENDING_HEREDOC_TAB_STRIPPING=()
  SHELL_COMMENT_FOUND="0"
  SHELL_COMMENT_INDEX="0"
  SHELL_IN_SINGLE_QUOTE="0"
  SHELL_IN_DOUBLE_QUOTE="0"
  SHELL_IN_ANSI_C_QUOTE="0"
  SHELL_PARENT_SINGLE_QUOTES=()
  SHELL_PARENT_DOUBLE_QUOTES=()
  SHELL_COMMAND_PAREN_DEPTHS=()
  SHELL_CONTEXT_TYPES=()
  SHELL_CASE_STATES=()
  LAST_COMMENT_LINE="0"
}

check_file_rules() {
  local path="${1:-}"
  check_require_executable_shebang "$path" "1" ""
  check_require_filename_matches_dirname "$path" "1" ""
  check_no_mixed_filename_casing "$path" "1" ""
}

scan_file_lines() {
  local path="${1:-}"
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    SCAN_LINE_NUMBER=$((SCAN_LINE_NUMBER + 1))
    scan_line "$path" "$SCAN_LINE_NUMBER" "$line"
  done < "$path"
}

scan_line() {
  local path="${1:-}"
  local line_number="${2:-}"
  local raw_line="${3:-}"
  local line
  CURRENT_LINE_TEXT="$raw_line"
  comment_policy_consumes_line "$path" "$line_number" "$raw_line" && return
  line="$(normalized_code_line "$raw_line")"
  [[ -z "$line" ]] && return
  run_line_checks "$path" "$line_number" "$line"
}

normalized_code_line() {
  local line="${1:-}"
  line="$(strip_comment "$line")"
  trim "$line"
}

invalidate_comment_rule_state() {
  COMMENT_RULE_STATE_READY="0"
}

prepare_comment_rule_state() {
  COMMENT_RULES_ENABLED="0"
  NO_UNMATCHED_COMMENTS_ENABLED="0"
  NO_AUTOMATED_COMMENT_ATTRIBUTION_ENABLED="0"
  NO_STACKED_COMMENTS_ENABLED="0"
  rule_enabled "LEG041" && NO_UNMATCHED_COMMENTS_ENABLED="1"
  rule_enabled "LEG042" && NO_AUTOMATED_COMMENT_ATTRIBUTION_ENABLED="1"
  rule_enabled "LEG043" && NO_STACKED_COMMENTS_ENABLED="1"
  [[ "$NO_UNMATCHED_COMMENTS_ENABLED$NO_AUTOMATED_COMMENT_ATTRIBUTION_ENABLED$NO_STACKED_COMMENTS_ENABLED" != "000" ]] && COMMENT_RULES_ENABLED="1"
  COMMENT_RULE_STATE_READY="1"
}

ensure_comment_rule_state() {
  [[ "$COMMENT_RULE_STATE_READY" == "1" ]] && return
  prepare_comment_rule_state
}

comment_policy_consumes_line() {
  local path="${1:-}"
  local line_number="${2:-}"
  local line="${3:-}"
  ensure_comment_rule_state
  [[ "$COMMENT_RULES_ENABLED" == "1" ]] || return 1
  heredoc_payload_line "$line" && return 0
  scan_shell_comment_line "$line"
  run_scanned_comment_checks "$path" "$line_number" "$line"
  activate_pending_heredocs
  return 1
}

run_scanned_comment_checks() {
  local path="${1:-}"
  local line_number="${2:-}"
  local line="${3:-}"
  local index body
  [[ "$SHELL_COMMENT_FOUND" == "1" ]] || return
  index="$SHELL_COMMENT_INDEX"
  body="${line:$((index + 1))}"
  shell_comment_ignored "$index" "$body" && return
  [[ "$NO_STACKED_COMMENTS_ENABLED" == "1" ]] && check_stacked_comment_line "$path" "$line_number" "$index"
  [[ "$NO_AUTOMATED_COMMENT_ATTRIBUTION_ENABLED" == "1" ]] && check_automated_comment_body "$path" "$line_number" "$index" "$body"
  [[ "$NO_UNMATCHED_COMMENTS_ENABLED" == "1" ]] && check_unmatched_comment_body "$path" "$line_number" "$index" "$body"
}

heredoc_payload_line() {
  local line="${1:-}"
  local delimiter
  (( ${#HEREDOC_DELIMITERS[@]} > 0 )) || return 1
  delimiter="${HEREDOC_DELIMITERS[0]}"
  [[ "${HEREDOC_TAB_STRIPPING[0]}" == "1" ]] && line="$(strip_leading_tabs "$line")"
  [[ "$line" == "$delimiter" ]] && close_heredoc
  return 0
}

strip_leading_tabs() {
  local value="${1:-}"
  while [[ "$value" == $'\t'* ]]; do
    value="${value#$'\t'}"
  done
  printf '%s\n' "$value"
}

close_heredoc() {
  HEREDOC_DELIMITERS=("${HEREDOC_DELIMITERS[@]:1}")
  HEREDOC_TAB_STRIPPING=("${HEREDOC_TAB_STRIPPING[@]:1}")
}

scan_shell_comment_line() {
  local line="${1:-}"
  local index char
  reset_shell_comment_line_state
  for ((index = 0; index < ${#line}; index++)); do
    char="${line:index:1}"
    shell_scan_consumes_escaped && continue
    shell_scan_starts_escape "$char" && continue
    shell_command_substitution_opens "$line" "$index" && index=$((index + 1)) && continue
    shell_backtick_substitution_consumed "$char" && continue
    shell_scan_toggles_quote "$line" "$index" "$char" && continue
    update_shell_case_state "$line" "$index"
    shell_case_arm_parenthesis_consumed "$char" && continue
    shell_command_parenthesis_consumed "$char" && continue
    queue_heredoc_at "$line" "$index"
    shell_comment_starts_at "$line" "$index" "$char" "$SHELL_IN_SINGLE_QUOTE" "$SHELL_IN_DOUBLE_QUOTE" || continue
    record_shell_comment "$index"
    return
  done
}

reset_shell_comment_line_state() {
  SHELL_COMMENT_FOUND="0"
  SHELL_COMMENT_INDEX="0"
  SHELL_SCAN_ESCAPED="0"
}

record_shell_comment() {
  SHELL_COMMENT_FOUND="1"
  SHELL_COMMENT_INDEX="${1:-0}"
}

shell_scan_consumes_escaped() {
  [[ "$SHELL_SCAN_ESCAPED" == "1" ]] || return 1
  SHELL_SCAN_ESCAPED="0"
}

shell_scan_starts_escape() {
  local char="${1:-}"
  [[ "$char" == "\\" ]] || return 1
  [[ "$SHELL_IN_SINGLE_QUOTE" == "0" || "$SHELL_IN_ANSI_C_QUOTE" == "1" ]] || return 1
  SHELL_SCAN_ESCAPED="1"
}

shell_command_substitution_opens() {
  local line="${1:-}"
  local index="${2:-0}"
  [[ "${line:index:2}" == '$(' ]] || return 1
  [[ "$SHELL_IN_SINGLE_QUOTE" == "0" ]] || return 1
  open_shell_context "parenthesis" "1"
}

shell_backtick_substitution_consumed() {
  local char="${1:-}"
  local last
  [[ "$char" == '`' ]] || return 1
  [[ "$SHELL_IN_SINGLE_QUOTE" == "0" ]] || return 1
  last=$((${#SHELL_CONTEXT_TYPES[@]} - 1))
  backtick_context_open "$last" && close_shell_context "$last" && return
  open_shell_context "backtick" "0"
}

backtick_context_open() {
  local last="${1:--1}"
  (( last >= 0 )) || return 1
  [[ "${SHELL_CONTEXT_TYPES[$last]}" == "backtick" ]]
}

open_shell_context() {
  local type="${1:-}"
  local depth="${2:-0}"
  SHELL_PARENT_SINGLE_QUOTES+=("$SHELL_IN_SINGLE_QUOTE")
  SHELL_PARENT_DOUBLE_QUOTES+=("$SHELL_IN_DOUBLE_QUOTE")
  SHELL_COMMAND_PAREN_DEPTHS+=("$depth")
  SHELL_CONTEXT_TYPES+=("$type")
  SHELL_IN_SINGLE_QUOTE="0"
  SHELL_IN_DOUBLE_QUOTE="0"
  SHELL_IN_ANSI_C_QUOTE="0"
}

shell_scan_toggles_quote() {
  local line="${1:-}"
  local index="${2:-0}"
  local char="${3:-}"
  shell_single_quote_consumed "$line" "$index" "$char" && return 0
  double_quote_opens "$char" "$SHELL_IN_SINGLE_QUOTE" && SHELL_IN_DOUBLE_QUOTE=$((1 - SHELL_IN_DOUBLE_QUOTE)) && return 0
  return 1
}

shell_single_quote_consumed() {
  local line="${1:-}"
  local index="${2:-0}"
  local char="${3:-}"
  single_quote_opens "$char" "$SHELL_IN_DOUBLE_QUOTE" || return 1
  update_shell_single_quote "$line" "$index"
}

update_shell_single_quote() {
  local line="${1:-}"
  local index="${2:-0}"
  close_shell_single_quote && return
  SHELL_IN_SINGLE_QUOTE="1"
  ansi_c_quote_prefix_at "$line" "$index" && SHELL_IN_ANSI_C_QUOTE="1"
}

close_shell_single_quote() {
  [[ "$SHELL_IN_SINGLE_QUOTE" == "1" ]] || return 1
  SHELL_IN_SINGLE_QUOTE="0"
  SHELL_IN_ANSI_C_QUOTE="0"
}

ansi_c_quote_prefix_at() {
  local line="${1:-}"
  local index="${2:-0}"
  (( index > 0 )) || return 1
  [[ "${line:$((index - 1)):1}" == '$' ]]
}

update_shell_case_state() {
  local line="${1:-}"
  local index="${2:-0}"
  [[ "$SHELL_IN_SINGLE_QUOTE$SHELL_IN_DOUBLE_QUOTE" == "00" ]] || return
  shell_keyword_at "$line" "$index" "case" && SHELL_CASE_STATES+=("awaiting-in") && return
  shell_keyword_at "$line" "$index" "in" && open_shell_case_patterns && return
  shell_keyword_at "$line" "$index" "esac" && close_shell_case && return
  shell_case_terminator_at "$line" "$index" && open_next_shell_case_pattern
}

shell_keyword_at() {
  local line="${1:-}"
  local index="${2:-0}"
  local keyword="${3:-}"
  local before after
  [[ "${line:index:${#keyword}}" == "$keyword" ]] || return 1
  before="${line:$((index - 1)):1}"
  after="${line:$((index + ${#keyword})):1}"
  (( index == 0 )) || [[ ! "$before" =~ [[:alnum:]_] ]] || return 1
  [[ -z "$after" || ! "$after" =~ [[:alnum:]_] ]]
}

open_shell_case_patterns() {
  local last
  last=$((${#SHELL_CASE_STATES[@]} - 1))
  (( last >= 0 )) || return 1
  [[ "${SHELL_CASE_STATES[$last]}" == "awaiting-in" ]] || return 1
  SHELL_CASE_STATES[$last]="pattern"
}

close_shell_case() {
  local last
  last=$((${#SHELL_CASE_STATES[@]} - 1))
  (( last >= 0 )) || return 1
  SHELL_CASE_STATES=("${SHELL_CASE_STATES[@]:0:last}")
}

shell_case_terminator_at() {
  local line="${1:-}"
  local index="${2:-0}"
  local tail="${line:index:3}"
  case "$tail" in
    ";;"*|";&"*) return 0 ;;
  esac
  return 1
}

open_next_shell_case_pattern() {
  local last
  last=$((${#SHELL_CASE_STATES[@]} - 1))
  (( last >= 0 )) || return 1
  [[ "${SHELL_CASE_STATES[$last]}" == "body" ]] || return 1
  SHELL_CASE_STATES[$last]="pattern"
}

shell_case_arm_parenthesis_consumed() {
  local char="${1:-}"
  local last
  [[ "$char" == ")" ]] || return 1
  last=$((${#SHELL_CASE_STATES[@]} - 1))
  (( last >= 0 )) || return 1
  [[ "${SHELL_CASE_STATES[$last]}" == "pattern" ]] || return 1
  SHELL_CASE_STATES[$last]="body"
}

shell_command_parenthesis_consumed() {
  local char="${1:-}"
  local last
  [[ "$SHELL_IN_SINGLE_QUOTE$SHELL_IN_DOUBLE_QUOTE" == "00" ]] || return 1
  last=$((${#SHELL_CONTEXT_TYPES[@]} - 1))
  (( last >= 0 )) || return 1
  [[ "${SHELL_CONTEXT_TYPES[$last]}" == "parenthesis" ]] || return 1
  [[ "$char" == "(" ]] && increment_shell_command_parenthesis "$last" && return 0
  [[ "$char" == ")" ]] || return 1
  close_shell_command_parenthesis "$last"
}

increment_shell_command_parenthesis() {
  local last="${1:-0}"
  SHELL_COMMAND_PAREN_DEPTHS[$last]=$((SHELL_COMMAND_PAREN_DEPTHS[$last] + 1))
}

close_shell_command_parenthesis() {
  local last="${1:-0}"
  local depth
  depth=$((SHELL_COMMAND_PAREN_DEPTHS[$last] - 1))
  shell_command_parenthesis_remains "$last" "$depth" && return
  close_shell_context "$last"
}

close_shell_context() {
  local last="${1:-0}"
  SHELL_IN_SINGLE_QUOTE="${SHELL_PARENT_SINGLE_QUOTES[$last]}"
  SHELL_IN_DOUBLE_QUOTE="${SHELL_PARENT_DOUBLE_QUOTES[$last]}"
  SHELL_IN_ANSI_C_QUOTE="0"
  SHELL_COMMAND_PAREN_DEPTHS=("${SHELL_COMMAND_PAREN_DEPTHS[@]:0:last}")
  SHELL_PARENT_SINGLE_QUOTES=("${SHELL_PARENT_SINGLE_QUOTES[@]:0:last}")
  SHELL_PARENT_DOUBLE_QUOTES=("${SHELL_PARENT_DOUBLE_QUOTES[@]:0:last}")
  SHELL_CONTEXT_TYPES=("${SHELL_CONTEXT_TYPES[@]:0:last}")
}

shell_command_parenthesis_remains() {
  local last="${1:-0}"
  local depth="${2:-0}"
  (( depth > 0 )) || return 1
  SHELL_COMMAND_PAREN_DEPTHS[$last]="$depth"
}

queue_heredoc_at() {
  local line="${1:-}"
  local index="${2:-0}"
  shell_heredoc_operator_at "$line" "$index" || return 1
  PARSED_HEREDOC_OPERATOR_INDEX="$index"
  parse_heredoc_opener "$line" || return 1
  queue_parsed_heredoc
}

shell_heredoc_operator_at() {
  local line="${1:-}"
  local index="${2:-0}"
  [[ "$SHELL_IN_SINGLE_QUOTE$SHELL_IN_DOUBLE_QUOTE" == "00" ]] || return 1
  [[ "${line:index:2}" == "<<" ]] || return 1
  [[ "${line:index:3}" != "<<<" ]] || return 1
  (( index == 0 )) || [[ "${line:$((index - 1)):1}" != "<" ]] || return 1
  heredoc_arithmetic_context "$line" "$index" && return 1
  return 0
}

heredoc_arithmetic_context() {
  local line="${1:-}"
  local index="${2:-0}"
  local prefix tail
  prefix="${line:0:index}"
  tail="${prefix##*"(("}"
  [[ "$tail" != "$prefix" ]] || return 1
  [[ "$tail" != *"))"* ]]
}

parse_heredoc_opener() {
  local line="${1:-}"
  local tail
  tail="${line:$((PARSED_HEREDOC_OPERATOR_INDEX + 2))}"
  PARSED_HEREDOC_TAB_STRIPPING="0"
  [[ "$tail" == -* ]] && PARSED_HEREDOC_TAB_STRIPPING="1" && tail="${tail#-}"
  tail="${tail#"${tail%%[![:space:]]*}"}"
  parse_heredoc_word "$tail" || return 1
  PARSED_HEREDOC_DELIMITER="$(clean_heredoc_delimiter "$PARSED_HEREDOC_TOKEN")"
  [[ -n "$PARSED_HEREDOC_DELIMITER" ]]
}

parse_heredoc_word() {
  local value="${1:-}"
  local index char in_single="0" in_double="0" escaped="0"
  PARSED_HEREDOC_TOKEN=""
  for ((index = 0; index < ${#value}; index++)); do
    char="${value:index:1}"
    [[ "$escaped" == "1" ]] && PARSED_HEREDOC_TOKEN+="$char" && escaped="0" && continue
    [[ "$char" == "\\" && "$in_single" == "0" ]] && PARSED_HEREDOC_TOKEN+="$char" && escaped="1" && continue
    [[ "$char" == "'" && "$in_double" == "0" ]] && in_single=$((1 - in_single))
    [[ "$char" == '"' && "$in_single" == "0" ]] && in_double=$((1 - in_double))
    heredoc_word_separator "$char" "$in_single" "$in_double" && break
    PARSED_HEREDOC_TOKEN+="$char"
  done
  [[ -n "$PARSED_HEREDOC_TOKEN" ]]
}

heredoc_word_separator() {
  local char="${1:-}"
  [[ "${2:-0}${3:-0}" == "00" ]] || return 1
  [[ "$char" =~ [[:space:]] ]] && return 0
  [[ ";|&()<>" == *"$char"* ]]
}

clean_heredoc_delimiter() {
  local token="${1:-}"
  local index char result="" in_single="0" in_double="0" escaped="0"
  for ((index = 0; index < ${#token}; index++)); do
    char="${token:index:1}"
    [[ "$escaped" == "1" ]] && result+="$char" && escaped="0" && continue
    heredoc_delimiter_escape_starts "$token" "$index" "$in_single" "$in_double" && escaped="1" && continue
    single_quote_opens "$char" "$in_double" && in_single=$((1 - in_single)) && continue
    double_quote_opens "$char" "$in_single" && in_double=$((1 - in_double)) && continue
    result+="$char"
  done
  printf '%s\n' "$result"
}

heredoc_delimiter_escape_starts() {
  local token="${1:-}"
  local index="${2:-0}"
  local in_single="${3:-0}"
  local in_double="${4:-0}"
  local next
  [[ "${token:index:1}" == "\\" ]] || return 1
  [[ "$in_single" == "0" ]] || return 1
  [[ "$in_double" == "0" ]] && return 0
  next="${token:$((index + 1)):1}"
  case "$next" in
    '$'|'`'|'"'|"\\") return 0 ;;
  esac
  return 1
}

queue_parsed_heredoc() {
  PENDING_HEREDOC_DELIMITERS+=("$PARSED_HEREDOC_DELIMITER")
  PENDING_HEREDOC_TAB_STRIPPING+=("$PARSED_HEREDOC_TAB_STRIPPING")
}

activate_pending_heredocs() {
  [[ "$SHELL_SCAN_ESCAPED" == "0" ]] || return
  (( ${#PENDING_HEREDOC_DELIMITERS[@]} > 0 )) || return
  HEREDOC_DELIMITERS+=("${PENDING_HEREDOC_DELIMITERS[@]}")
  HEREDOC_TAB_STRIPPING+=("${PENDING_HEREDOC_TAB_STRIPPING[@]}")
  PENDING_HEREDOC_DELIMITERS=()
  PENDING_HEREDOC_TAB_STRIPPING=()
}

run_line_checks() {
  local path="${1:-}"
  local line_number="${2:-}"
  local line="${3:-}"
  close_completed_blocks "$line"
  run_stateless_line_checks "$path" "$line_number" "$line"
  update_state_from_line "$path" "$line_number" "$line"
}

run_stateless_line_checks() {
  local path="${1:-}"
  local line_number="${2:-}"
  local line="${3:-}"
  check_max_expression_operators "$path" "$line_number" "$line"
  check_prefer_object_lookup "$path" "$line_number" "$line"
  check_no_direct_shell_bin_smoke "$path" "$line_number" "$line"
  check_no_bool_literal_args "$path" "$line_number" "$line"
  check_prefer_functions "$path" "$line_number" "$line"
  check_use_defaults_in_functions "$path" "$line_number" "$line"
}

update_state_from_line() {
  local path="${1:-}"
  local line_number="${2:-}"
  local line="${3:-}"
  update_function_state "$path" "$line_number" "$line"
  update_if_state "$path" "$line_number" "$line"
  update_loop_state "$path" "$line_number" "$line"
  update_case_state "$path" "$line_number" "$line"
  update_exit_state "$line"
}

close_completed_blocks() {
  local line="${1:-}"
  case "$line" in
    fi*) close_if_block ;;
    done*) close_loop_block ;;
    esac*) close_control_flow ;;
  esac
}

close_if_block() {
  (( IF_DEPTH > 0 )) && IF_DEPTH=$((IF_DEPTH - 1))
  close_control_flow
}

close_loop_block() {
  (( LOOP_DEPTH > 0 )) && LOOP_DEPTH=$((LOOP_DEPTH - 1))
  close_control_flow
}

close_control_flow() {
  (( CONTROL_FLOW_DEPTH > 0 )) && CONTROL_FLOW_DEPTH=$((CONTROL_FLOW_DEPTH - 1))
}

update_function_state() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-$SCAN_LINE_NUMBER}"
  local line="${3:-}"
  maybe_open_function "$path" "$line_number" "$line"
  maybe_close_function "$path" "$line_number" "$line"
}

maybe_open_function() {
  local path="${1:-}"
  local line_number="${2:-}"
  local line="${3:-}"
  [[ "$IN_FUNCTION" == "0" ]] || return
  maybe_open_pending_function "$path" "$line_number" "$line" && return
  is_function_open "$line" || maybe_remember_pending_function "$line_number" "$line"
  is_function_open "$line" || return
  remember_function_name "$line"
  handle_inline_function "$path" "$line_number" "$line" && return
  IN_FUNCTION="1"
  FUNCTION_START_LINE="$line_number"
}

maybe_open_pending_function() {
  local path="${1:-}"
  local line_number="${2:-}"
  local line="${3:-}"
  [[ "$PENDING_FUNCTION_DECLARATION" == "1" ]] || return 1
  ensure_pending_function_brace_line "$line" || return 1
  handle_pending_inline_function "$path" "$line_number" "$line" && return
  IN_FUNCTION="1"
  FUNCTION_START_LINE="$PENDING_FUNCTION_START_LINE"
  clear_pending_function
}

ensure_pending_function_brace_line() {
  local line="${1:-}"
  pending_function_brace_line "$line" && return 0
  clear_pending_function
  return 1
}

handle_pending_inline_function() {
  local path="${1:-}"
  local line_number="${2:-}"
  local line="${3:-}"
  inline_brace_line "$line" || return 1
  check_max_function_lines "$path" "$PENDING_FUNCTION_START_LINE" "$line_number"
  clear_pending_function
}

clear_pending_function() {
  PENDING_FUNCTION_DECLARATION="0"
  PENDING_FUNCTION_START_LINE="0"
}

maybe_close_function() {
  local path="${1:-}"
  local line_number="${2:-}"
  local line="${3:-}"
  [[ "$IN_FUNCTION" == "1" ]] || return
  [[ "$line" == "}"* ]] || return
  check_max_function_lines "$path" "$FUNCTION_START_LINE" "$line_number"
  IN_FUNCTION="0"
}

is_function_open() {
  local line="${1:-}"
  [[ "$line" =~ ^(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_:-]*[[:space:]]*(\(\))?[[:space:]]*\{ ]]
}

maybe_remember_pending_function() {
  local line_number="${1:-}"
  local line="${2:-}"
  local name
  name="$(function_declaration_name "$line")"
  [[ -z "$name" ]] && return
  FUNCTION_NAMES+=("$name")
  PENDING_FUNCTION_DECLARATION="1"
  PENDING_FUNCTION_START_LINE="$line_number"
}

function_declaration_name() {
  local line="${1:-}"
  function_keyword_declaration_name "$line" && return
  compact_function_declaration_name "$line"
}

function_keyword_declaration_name() {
  local line="${1:-}"
  local keyword name extra
  read -r keyword name extra <<< "$line"
  [[ "$keyword" == "function" ]] || return 1
  [[ -z "$extra" ]] || return 1
  name="${name%%()*}"
  shell_identifier "$name" || return 1
  printf '%s\n' "$name"
}

compact_function_declaration_name() {
  local line="${1:-}"
  local name="${line%%()*}"
  [[ "$name" != "$line" ]] || return 1
  [[ "$line" == "$name()" ]] || return 1
  shell_identifier "$name" || return 1
  printf '%s\n' "$name"
}

remember_function_name() {
  local line="${1:-}"
  local name
  name="$(function_name_from_open "$line")"
  [[ -n "$name" ]] && FUNCTION_NAMES+=("$name")
}

function_name_from_open() {
  local line="${1:-}"
  function_keyword_name "$line" && return
  compact_function_name "$line" && return
  spaced_function_name "$line"
}

function_keyword_name() {
  local line="${1:-}"
  local keyword name
  read -r keyword name _ <<< "$line"
  [[ "$keyword" == "function" ]] || return 1
  name="${name%%()*}"
  printf '%s\n' "$name"
}

compact_function_name() {
  local line="${1:-}"
  local name="${line%%()*}"
  [[ "$name" != "$line" ]] || return 1
  shell_identifier "$name" || return 1
  printf '%s\n' "$name"
}

spaced_function_name() {
  local line="${1:-}"
  local name
  read -r name _ <<< "$line"
  shell_identifier "$name" || return 1
  printf '%s\n' "$name"
}

shell_identifier() {
  local value="${1:-}"
  [[ "$value" =~ ^[A-Za-z_][A-Za-z0-9_:-]*$ ]]
}

update_if_state() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-$SCAN_LINE_NUMBER}"
  local line="${3:-}"
  handle_else_line "$path" "$line_number" "$line" && return
  handle_elif_line "$path" "$line_number" "$line" && return
  handle_if_line "$path" "$line_number" "$line"
}

handle_else_line() {
  local path="${1:-}"
  local line_number="${2:-}"
  local line="${3:-}"
  [[ "$line" == else* ]] || return 1
  check_prefer_early_return "$path" "$line_number" "$line"
  mark_current_if_else
}

handle_elif_line() {
  local path="${1:-}"
  local line_number="${2:-}"
  local line="${3:-}"
  [[ "$line" == elif* ]] || return 1
  check_hoist_if_operators "$path" "$line_number" "$line"
  check_prefer_case_over_long_if_chain "$path" "$line_number" "$line"
}

handle_if_line() {
  local path="${1:-}"
  local line_number="${2:-}"
  local line="${3:-}"
  [[ "$line" == if[[:space:]]* ]] || return
  check_hoist_if_operators "$path" "$line_number" "$line"
  check_prefer_guard_clauses "$path" "$line_number" "$line"
  open_if_block "$path" "$line_number" "$line"
}

open_if_block() {
  local path="${1:-}"
  local line_number="${2:-}"
  local line="${3:-}"
  open_control_flow "$path" "$line_number"
  IF_DEPTH=$((IF_DEPTH + 1))
  IF_THEN_EXIT[IF_DEPTH]="0"
  IF_COMPARE_NAME[IF_DEPTH]="$(comparison_left_name "$line")"
  IF_COMPARE_COUNT[IF_DEPTH]="1"
  IF_COMPARE_REPORTED[IF_DEPTH]="0"
}

mark_current_if_else() {
  (( IF_DEPTH > 0 )) && IF_THEN_EXIT[IF_DEPTH]="else"
}

update_loop_state() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-$SCAN_LINE_NUMBER}"
  local line="${3:-}"
  is_loop_line "$line" || return
  check_loop_condition "$path" "$line_number" "$line"
  check_no_quadratic_patterns "$path" "$line_number" "$line"
  LOOP_DEPTH=$((LOOP_DEPTH + 1))
  open_control_flow "$path" "$line_number"
}

is_loop_line() {
  local line="${1:-}"
  [[ "$line" == for[[:space:]]* ]] && return 0
  [[ "$line" == while[[:space:]]* ]] && return 0
  [[ "$line" == until[[:space:]]* ]]
}

check_loop_condition() {
  local path="${1:-}"
  local line_number="${2:-}"
  local line="${3:-}"
  [[ "$line" == for[[:space:]]* ]] && return
  check_hoist_if_operators "$path" "$line_number" "$line"
}

update_case_state() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-$SCAN_LINE_NUMBER}"
  local line="${3:-}"
  [[ "$line" == case[[:space:]]* ]] || return
  open_control_flow "$path" "$line_number"
}

open_control_flow() {
  local path="${1:-}"
  local line_number="${2:-}"
  CONTROL_FLOW_DEPTH=$((CONTROL_FLOW_DEPTH + 1))
  check_max_control_flow_depth "$path" "$line_number" "$CONTROL_FLOW_DEPTH"
}

update_exit_state() {
  local line="${1:-}"
  (( IF_DEPTH == 0 )) && return
  [[ "${IF_THEN_EXIT[$IF_DEPTH]}" == "else" ]] && return
  command_exits "$line" && IF_THEN_EXIT[IF_DEPTH]="1"
}

command_exits() {
  local line="${1:-}"
  [[ "$line" =~ ^(return|exit|break|continue)([[:space:]]|$) ]]
}

check_max_expression_operators() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-$SCAN_LINE_NUMBER}"
  local expression="${3:-$CURRENT_LINE_TEXT}"
  line_starts_control "$expression" && return
  local count
  count="$(count_expression_operators "$expression")"
  (( count <= MAX_EXPRESSION_OPERATORS )) && return
  report_max_expression_operators "$path" "$line_number" "$count"
}

report_max_expression_operators() {
  local path="${1:-}"
  local line_number="${2:-}"
  local count="${3:-}"
  local message
  message="Expression has $count legibility operators (max $MAX_EXPRESSION_OPERATORS). Extract named commands or values."
  add_diag "$path" "$line_number" "1" "LEG001" "$message"
}

check_hoist_if_operators() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-$SCAN_LINE_NUMBER}"
  local line="${3:-$CURRENT_LINE_TEXT}"
  local condition count
  condition="$(condition_text "$line")"
  count="$(count_condition_operators "$condition")"
  (( count <= MAX_CONDITION_OPERATORS )) && return
  report_hoist_if_operators "$path" "$line_number" "$count"
}

report_hoist_if_operators() {
  local path="${1:-}"
  local line_number="${2:-}"
  local count="${3:-}"
  local message
  message="Condition has $count legibility operators (max $MAX_CONDITION_OPERATORS). Hoist it into a named check."
  add_diag "$path" "$line_number" "1" "LEG002" "$message"
}

check_max_control_flow_depth() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-$SCAN_LINE_NUMBER}"
  local depth="${3:-$CONTROL_FLOW_DEPTH}"
  (( depth <= MAX_CONTROL_FLOW_DEPTH )) && return
  local message
  message="Control-flow depth is $depth (max $MAX_CONTROL_FLOW_DEPTH). Prefer guard clauses or extracted functions."
  add_diag "$path" "$line_number" "1" "LEG003" "$message"
}

check_no_quadratic_patterns() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-$SCAN_LINE_NUMBER}"
  local line="${3:-$CURRENT_LINE_TEXT}"
  (( LOOP_DEPTH > 0 )) || return
  local message
  message="Nested loop detected. Consider a lookup, case statement, or extracted function."
  add_diag "$path" "$line_number" "1" "LEG005" "$message"
}

check_prefer_early_return() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-$SCAN_LINE_NUMBER}"
  local line="${3:-$CURRENT_LINE_TEXT}"
  [[ "$line" == else* ]] || return
  (( IF_DEPTH > 0 )) || return
  [[ "${IF_THEN_EXIT[$IF_DEPTH]}" == "1" ]] || return
  local message
  message="Avoid else after a branch exits. Return or continue early and keep the follow-up path unindented."
  add_diag "$path" "$line_number" "1" "LEG009" "$message"
}

check_prefer_guard_clauses() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-$SCAN_LINE_NUMBER}"
  local line="${3:-$CURRENT_LINE_TEXT}"
  [[ "$IN_FUNCTION" == "1" ]] || return
  [[ "$line" == if[[:space:]]* ]] || return
  [[ "$line" == *"then"* ]] || return
  local message
  message="Prefer a guard clause before the main path instead of wrapping function logic in an if block."
  add_diag "$path" "$line_number" "1" "LEG010" "$message"
}

check_require_executable_shebang() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-1}"
  [[ "${#EXECUTABLE_ENTRY_PATTERNS[@]}" -gt 0 ]] || return
  path_matches_any "$path" "${EXECUTABLE_ENTRY_PATTERNS[@]}" || return
  file_has_allowed_shebang "$path" && return
  add_diag "$path" "$line_number" "1" "LEG016" "Executable shell entry file has no accepted shebang."
}

check_no_direct_shell_bin_smoke() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-$SCAN_LINE_NUMBER}"
  local line="${3:-$CURRENT_LINE_TEXT}"
  local shell entry
  shell="$(first_word "$line")"
  shell_runtime_allowed "$shell" || return
  entry="$(direct_entry_from_line "$line")"
  [[ -z "$entry" ]] && return
  report_no_direct_shell_bin_smoke "$path" "$line_number" "$shell" "$entry"
}

report_no_direct_shell_bin_smoke() {
  local path="${1:-}"
  local line_number="${2:-}"
  local shell="${3:-}"
  local entry="${4:-}"
  local message
  message="Smoke tests should execute the installed command, not \`$shell $entry\`, so packaging and shebangs are exercised."
  add_diag "$path" "$line_number" "1" "LEG017" "$message"
}

check_prefer_object_lookup() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-$SCAN_LINE_NUMBER}"
  local line="${3:-$CURRENT_LINE_TEXT}"
  local count name
  name="$(comparison_left_name "$line")"
  [[ -z "$name" ]] && return
  count="$(count_occurrences "$line" "$name")"
  (( count < MIN_OBJECT_LOOKUP_CHAIN_LENGTH )) && return
  local message
  message="Replace repeated $name equality checks with a case statement or lookup."
  add_diag "$path" "$line_number" "1" "LEG024" "$message"
}

check_require_filename_matches_dirname() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-1}"
  local file parent base depth
  depth="$(path_parent_depth "$path")"
  (( depth < MIN_DIRNAME_MATCH_DEPTH )) && return
  parent="$(basename "$(dirname "$path")")"
  file="$(filename_without_extension "$path")"
  base="${file%%.*}"
  filename_base_allowed "$base" "$parent" && return
  report_filename_mismatch "$path" "$line_number" "$file" "$parent"
}

report_filename_mismatch() {
  local path="${1:-}"
  local line_number="${2:-}"
  local file="${3:-}"
  local parent="${4:-}"
  local message
  message="Filename \"$file\" does not match parent directory \"$parent\"."
  add_diag "$path" "$line_number" "1" "LEG025" "$message"
}

check_no_mixed_filename_casing() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-1}"
  local name
  name="$(filename_base "$path")"
  filename_casing_mixed "$name" || return
  local message
  message="Filename \"$name\" mixes casing conventions. Use one casing convention."
  add_diag "$path" "$line_number" "1" "LEG026" "$message"
}

check_prefer_case_over_long_if_chain() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-$SCAN_LINE_NUMBER}"
  local line="${3:-$CURRENT_LINE_TEXT}"
  track_if_chain_comparison "$path" "$line_number" "$line"
}

check_no_bool_literal_args() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-$SCAN_LINE_NUMBER}"
  local line="${3:-$CURRENT_LINE_TEXT}"
  has_bool_literal_arg "$line" || return
  local message
  message="Avoid boolean literal arguments. Name the option before passing it."
  add_diag "$path" "$line_number" "1" "LEG035" "$message"
}

check_max_function_lines() {
  local path="${1:-$SCAN_PATH}"
  local start_line="${2:-$FUNCTION_START_LINE}"
  local end_line="${3:-$SCAN_LINE_NUMBER}"
  local lines
  lines=$((end_line - start_line + 1))
  (( lines <= MAX_FUNCTION_LINES )) && return
  local message
  message="Function has $lines lines (max $MAX_FUNCTION_LINES). Extract focused helper functions."
  add_diag "$path" "$start_line" "1" "LEG038" "$message"
}

check_prefer_functions() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-$SCAN_LINE_NUMBER}"
  local line="${3:-$CURRENT_LINE_TEXT}"
  [[ "$PREFER_FUNCTIONS_REPORTED" == "0" ]] || return
  [[ "$IN_FUNCTION" == "0" ]] || return
  (( CONTROL_FLOW_DEPTH == 0 )) || return
  top_level_line_allowed "$line" && return
  local message
  message="Move top-level script logic into named functions and keep only setup plus function dispatch at the top level."
  add_diag "$path" "$line_number" "1" "LEG039" "$message"
  PREFER_FUNCTIONS_REPORTED="1"
}

check_use_defaults_in_functions() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-$SCAN_LINE_NUMBER}"
  local line="${3:-$CURRENT_LINE_TEXT}"
  local scoped_line
  scoped_line="$(function_scoped_line "$line")" || return
  has_unguarded_arg_assignment "$scoped_line" || return
  local message
  message="Use a default or required-argument expansion when binding positional parameters inside functions."
  add_diag "$path" "$line_number" "1" "LEG040" "$message"
}

check_no_unmatched_comments() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-$SCAN_LINE_NUMBER}"
  local line="${3:-$CURRENT_LINE_TEXT}"
  local index body
  rule_enabled "LEG041" || return
  index="$(shell_comment_index "$line")" || return
  body="${line:$((index + 1))}"
  shell_comment_ignored "$index" "$body" && return
  check_unmatched_comment_body "$path" "$line_number" "$index" "$body"
}

check_unmatched_comment_body() {
  local path="${1:-}"
  local line_number="${2:-}"
  local index="${3:-0}"
  local body="${4:-}"
  comment_allowed "$body" && return
  report_no_unmatched_comment "$path" "$line_number" "$index"
}

report_no_unmatched_comment() {
  local path="${1:-}"
  local line_number="${2:-}"
  local index="${3:-0}"
  local column message
  column=$((index + 1))
  message="Comment does not match a configured matcher, prefix identifier, or suffix identifier."
  add_diag "$path" "$line_number" "$column" "LEG041" "$message"
}

check_no_automated_comment_attribution() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-$SCAN_LINE_NUMBER}"
  local line="${3:-$CURRENT_LINE_TEXT}"
  local index body normalized_body normalized_author
  rule_enabled "LEG042" || return
  index="$(shell_comment_index "$line")" || return
  body="${line:$((index + 1))}"
  shell_comment_ignored "$index" "$body" && return
  check_automated_comment_body "$path" "$line_number" "$index" "$body"
}

check_automated_comment_body() {
  local path="${1:-}"
  local line_number="${2:-}"
  local index="${3:-0}"
  local body="${4:-}"
  local normalized_body normalized_author lower_body
  prepare_automated_comment_identifiers
  (( ${#NORMALIZED_AUTOMATED_COMMENT_IDENTIFIERS[@]} > 0 )) || return
  normalized_body="$(normalize_attribution_text "$body")"
  lower_body="$(lowercase "$body")"
  normalized_author=""
  [[ "$lower_body" == *"@author"* ]] && normalized_author="$(normalized_comment_author "$body")"
  automated_comment_identifier "$body" "$normalized_body" "$normalized_author" || return
  report_automated_comment_attribution "$path" "$line_number" "$index" "$AUTOMATED_COMMENT_IDENTIFIER"
}

report_automated_comment_attribution() {
  local path="${1:-}"
  local line_number="${2:-}"
  local index="${3:-0}"
  local identifier="${4:-}"
  local column message
  column=$((index + 1))
  message="Comment contains the prohibited attribution \"$identifier\"."
  add_diag "$path" "$line_number" "$column" "LEG042" "$message"
}

check_no_stacked_comments() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-$SCAN_LINE_NUMBER}"
  local line="${3:-$CURRENT_LINE_TEXT}"
  local index body
  rule_enabled "LEG043" || return
  index="$(shell_comment_index "$line")" || return
  body="${line:$((index + 1))}"
  shell_comment_ignored "$index" "$body" && return
  check_stacked_comment_line "$path" "$line_number" "$index"
}

check_stacked_comment_line() {
  local path="${1:-}"
  local line_number="${2:-0}"
  local index="${3:-0}"
  stacked_comment_follows "$line_number" && report_stacked_comment "$path" "$line_number" "$index"
  LAST_COMMENT_LINE="$line_number"
}

stacked_comment_follows() {
  local line_number="${1:-0}"
  (( LAST_COMMENT_LINE > 0 )) || return 1
  (( line_number == LAST_COMMENT_LINE + 1 ))
}

report_stacked_comment() {
  local path="${1:-}"
  local line_number="${2:-0}"
  local index="${3:-0}"
  local column message
  column=$((index + 1))
  message="Update or remove the adjacent comment instead of stacking another comment."
  add_diag "$path" "$line_number" "$column" "LEG043" "$message"
}

automated_comment_identifier() {
  local body="${1:-}"
  local normalized_body="${2:-}"
  local normalized_author="${3:-}"
  local index normalized_identifier
  AUTOMATED_COMMENT_IDENTIFIER=""
  for index in "${!NORMALIZED_AUTOMATED_COMMENT_IDENTIFIERS[@]}"; do
    normalized_identifier="${NORMALIZED_AUTOMATED_COMMENT_IDENTIFIERS[$index]}"
    comment_attributes_to "$body" "$normalized_body" "$normalized_author" "$normalized_identifier" "${AUTOMATED_COMMENT_IDENTIFIERS[$index]}" || continue
    AUTOMATED_COMMENT_IDENTIFIER="${AUTOMATED_COMMENT_IDENTIFIERS[$index]}"
    return 0
  done
  return 1
}

prepare_automated_comment_identifiers() {
  local identifier
  automated_comment_identifier_cache_current && return
  if [[ "${#AUTOMATED_COMMENT_IDENTIFIERS[@]}" -eq 0 ]]; then
    CACHED_AUTOMATED_COMMENT_IDENTIFIERS=()
    NORMALIZED_AUTOMATED_COMMENT_IDENTIFIERS=()
    return
  fi
  CACHED_AUTOMATED_COMMENT_IDENTIFIERS=("${AUTOMATED_COMMENT_IDENTIFIERS[@]}")
  NORMALIZED_AUTOMATED_COMMENT_IDENTIFIERS=()
  for identifier in "${AUTOMATED_COMMENT_IDENTIFIERS[@]}"; do
    NORMALIZED_AUTOMATED_COMMENT_IDENTIFIERS+=("$(normalize_attribution_text "$identifier")")
  done
}

automated_comment_identifier_cache_current() {
  local index
  [[ "${#AUTOMATED_COMMENT_IDENTIFIERS[@]}" -eq "${#CACHED_AUTOMATED_COMMENT_IDENTIFIERS[@]}" ]] || return 1
  [[ "${#AUTOMATED_COMMENT_IDENTIFIERS[@]}" -eq "${#NORMALIZED_AUTOMATED_COMMENT_IDENTIFIERS[@]}" ]] || return 1
  [[ "${#AUTOMATED_COMMENT_IDENTIFIERS[@]}" -eq 0 ]] && return 0
  for index in "${!AUTOMATED_COMMENT_IDENTIFIERS[@]}"; do
    [[ "${AUTOMATED_COMMENT_IDENTIFIERS[$index]}" == "${CACHED_AUTOMATED_COMMENT_IDENTIFIERS[$index]}" ]] || return 1
  done
}

comment_attributes_to() {
  local body="${1:-}"
  local normalized_body="${2:-}"
  local normalized_author="${3:-}"
  local normalized_identifier="${4:-}"
  local identifier="${5:-}"
  [[ -n "$normalized_identifier" ]] || return 1
  comment_author_matches "$normalized_author" "$normalized_identifier" && return 0
  comment_has_generation_signature "$body" "$normalized_body" "$normalized_identifier" "$identifier"
}

comment_author_matches() {
  local author="${1:-}"
  local identifier="${2:-}"
  [[ -n "$author" ]] || return 1
  phrase_present "$author" "$identifier"
}

normalized_comment_author() {
  local body="${1:-}"
  local pattern='(^|[[:space:]])@author([[:space:]]|:)+(.+)$'
  body="$(lowercase "$body")"
  [[ "$body" =~ $pattern ]] || return 0
  normalize_attribution_text "${BASH_REMATCH[3]}"
}

comment_has_generation_signature() {
  local body="${1:-}"
  local normalized_body="${2:-}"
  local normalized_identifier="${3:-}"
  local identifier="${4:-}"
  local verb
  for verb in authored created generated produced written; do
    generation_signature_present "$body" "$normalized_body" "$normalized_identifier" "$identifier" "$verb" && return 0
  done
  return 1
}

generation_signature_present() {
  local body="${1:-}"
  local normalized_body="${2:-}"
  local normalized_identifier="${3:-}"
  local identifier="${4:-}"
  local verb="${5:-}"
  phrase_present "$normalized_body" "$normalized_identifier $verb" && return 0
  passive_generation_signature "$body" "$identifier" "$verb"
}

passive_generation_signature() {
  local body="${1:-}"
  local identifier="${2:-}"
  local verb="${3:-}"
  body="$(lowercase "$body")"
  identifier="$(lowercase "$identifier")"
  passive_attribution_phrase_present "$body" "$verb by $identifier" && return 0
  passive_attribution_phrase_present "$body" "$verb by a $identifier" && return 0
  passive_attribution_phrase_present "$body" "$verb by an $identifier"
}

passive_attribution_phrase_present() {
  local body="${1:-}"
  local phrase="${2:-}"
  local prefix suffix
  while [[ "$body" == *"$phrase"* ]]; do
    prefix="${body%%"$phrase"*}"
    suffix="${body#*"$phrase"}"
    attribution_phrase_boundaries "$prefix" "$suffix" && return 0
    body="$suffix"
  done
  return 1
}

attribution_phrase_boundaries() {
  local prefix="${1:-}"
  local raw_suffix="${2:-}"
  local suffix first last terminators
  suffix="$(trim "$raw_suffix")"
  last="${prefix:$((${#prefix} - 1)):1}"
  [[ -z "$prefix" || ! "$last" =~ [[:alnum:]_] ]] || return 1
  attribution_conjunction_follows "$raw_suffix" && return 0
  first="${suffix:0:1}"
  [[ -z "$first" ]] && return 0
  terminators=".,;:!?)]}"
  [[ "$terminators" == *"$first"* ]]
}

attribution_conjunction_follows() {
  local suffix="${1:-}"
  local word
  [[ "$suffix" == [[:space:]]* ]] || return 1
  read -r word _ <<< "$suffix"
  case "$word" in
    and|but|for|nor) return 0 ;;
    or|so|yet) return 0 ;;
  esac
  return 1
}

normalize_attribution_text() {
  local value="${1:-}"
  local -a words
  local IFS=" "
  value="$(lowercase "$value")"
  value="${value//[![:alnum:]]/ }"
  read -r -a words <<< "$value"
  printf '%s\n' "${words[*]}"
}

phrase_present() {
  local value="${1:-}"
  local phrase="${2:-}"
  [[ " $value " == *" $phrase "* ]]
}

function_scoped_line() {
  local line="${1:-}"
  [[ "$IN_FUNCTION" == "1" ]] && printf '%s\n' "$line" && return
  [[ "$PENDING_FUNCTION_DECLARATION" == "1" ]] && brace_opening_body "$line" && return
  function_opening_body "$line"
}

function_opening_body() {
  local line="${1:-}"
  is_function_open "$line" || return 1
  brace_opening_body "$line"
}

brace_opening_body() {
  local line="${1:-}"
  [[ "$line" == *"{"* ]] || return 1
  line="${line#*\{}"
  [[ "$line" == *"}"* ]] && line="${line%\}*}"
  printf '%s\n' "$line"
}

handle_inline_function() {
  local path="${1:-}"
  local line_number="${2:-}"
  local line="${3:-}"
  inline_function_line "$line" || return 1
  check_max_function_lines "$path" "$line_number" "$line_number"
}

inline_function_line() {
  local line="${1:-}"
  is_function_open "$line" || return 1
  [[ "$line" == *"{"*"}"* ]]
}

inline_brace_line() {
  local line="${1:-}"
  [[ "$line" == "{"*"}"* ]]
}

top_level_line_allowed() {
  local line="${1:-}"
  [[ -z "$line" ]] && return 0
  pending_function_brace_line "$line" && return 0
  is_function_open "$line" && return 0
  function_declaration_name "$line" >/dev/null && return 0
  top_level_declaration_line "$line" && return 0
  top_level_block_close "$line" && return 0
  top_level_function_dispatch "$line"
}

pending_function_brace_line() {
  local line="${1:-}"
  [[ "$PENDING_FUNCTION_DECLARATION" == "1" ]] || return 1
  [[ "$line" == "{"* ]]
}

top_level_declaration_line() {
  local line="${1:-}"
  local word
  simple_assignment_line "$line" && return 0
  word="$(first_word "$line")"
  case "$word" in
    set) return 0 ;;
    shopt) return 0 ;;
    trap) return 0 ;;
    source) return 0 ;;
    .) return 0 ;;
    export) return 0 ;;
    readonly) return 0 ;;
    declare) return 0 ;;
    typeset) return 0 ;;
  esac
  return 1
}

simple_assignment_line() {
  local line="${1:-}"
  local name="${line%%=*}"
  [[ "$name" != "$line" ]] || return 1
  name="${name%+}"
  name="${name%%[*}"
  shell_identifier "$name"
}

top_level_block_close() {
  case "${1:-}" in
    "}"*) return 0 ;;
    fi*) return 0 ;;
    done*) return 0 ;;
    "esac"*) return 0 ;;
  esac
  return 1
}

top_level_function_dispatch() {
  local line="${1:-}"
  local command
  command="$(first_word "$line")"
  function_name_seen "$command"
}

function_name_seen() {
  local name="${1:-}"
  local function_name
  [[ "$name" == "main" ]] && return 0
  [[ "${#FUNCTION_NAMES[@]}" -gt 0 ]] || return 1
  for function_name in "${FUNCTION_NAMES[@]}"; do
    [[ "$function_name" == "$name" ]] && return 0
  done
  return 1
}

has_unguarded_arg_assignment() {
  local line="${1:-}"
  local segment
  local -a segments
  line="$(command_list_segments "$line")"
  IFS=';' read -r -a segments <<< "$line"
  [[ "${#segments[@]}" -gt 0 ]] || return 1
  for segment in "${segments[@]}"; do
    segment="$(trim "$segment")"
    assignment_segment_uses_unguarded_arg "$segment" && return 0
  done
  return 1
}

command_list_segments() {
  local line="${1:-}"
  line="${line//&&/;}"
  line="${line//||/;}"
  line="${line//|/;}"
  printf '%s\n' "$line"
}

assignment_segment_uses_unguarded_arg() {
  local segment="${1:-}"
  binding_assignment_segment "$segment" || return 1
  has_unguarded_positional_expansion "$segment"
}

binding_assignment_segment() {
  local segment="${1:-}"
  declaration_assignment_segment "$segment" && return 0
  simple_assignment_line "$segment"
}

declaration_assignment_segment() {
  local segment="${1:-}"
  local command
  command="$(first_word "$segment")"
  [[ "$segment" == *=* ]] || return 1
  declaration_command_supported "$command" || return 1
  declaration_has_global_option "$segment" && return 1
  return 0
}

declaration_command_supported() {
  case "${1:-}" in
    local|declare|typeset) return 0 ;;
  esac
  return 1
}

declaration_has_global_option() {
  local segment="${1:-}"
  local word
  for word in $segment; do
    [[ "$word" == *"="* ]] && return 1
    [[ "$word" == -*g* ]] && return 0
  done
  return 1
}

has_unguarded_positional_expansion() {
  local text="${1:-}"
  bare_positional_expansion "$text" && return 0
  braced_positional_expansion_unguarded "$text"
}

bare_positional_expansion() {
  local text="${1:-}"
  [[ "$text" =~ (^|[^\\])\$[1-9][0-9]* ]]
}

braced_positional_expansion_unguarded() {
  local text="${1:-}"
  local match suffix
  while [[ "$text" =~ \$\{([1-9][0-9]*)([^}]*)\} ]]; do
    match="${BASH_REMATCH[0]}"
    suffix="${BASH_REMATCH[2]}"
    positional_suffix_guarded "$suffix" || return 0
    text="${text#*"$match"}"
  done
  return 1
}

positional_suffix_guarded() {
  case "${1:-}" in
    :-*) return 0 ;;
    -*) return 0 ;;
    :=*) return 0 ;;
    =*) return 0 ;;
    :\?*) return 0 ;;
    \?*) return 0 ;;
  esac
  return 1
}

shell_comment_index() {
  local line="${1:-}"
  local index char in_double="0" escaped="0"
  COMMENT_PARSER_IN_SINGLE_QUOTE="0"
  COMMENT_PARSER_IN_ANSI_C_QUOTE="0"
  for ((index = 0; index < ${#line}; index++)); do
    char="${line:index:1}"
    [[ "$escaped" == "1" ]] && escaped="0" && continue
    comment_parser_escape_starts "$char" "$COMMENT_PARSER_IN_SINGLE_QUOTE" "$COMMENT_PARSER_IN_ANSI_C_QUOTE" && escaped="1" && continue
    comment_parser_single_quote_consumed "$line" "$index" "$char" "$in_double" && continue
    double_quote_opens "$char" "$COMMENT_PARSER_IN_SINGLE_QUOTE" && in_double="$(toggle_flag "$in_double")" && continue
    shell_comment_at "$line" "$index" "$char" "$COMMENT_PARSER_IN_SINGLE_QUOTE" "$in_double" && return
  done
  return 1
}

comment_parser_single_quote_consumed() {
  local line="${1:-}"
  local index="${2:-0}"
  local char="${3:-}"
  local in_double="${4:-0}"
  single_quote_opens "$char" "$in_double" || return 1
  [[ "$COMMENT_PARSER_IN_SINGLE_QUOTE" == "0" ]] && COMMENT_PARSER_IN_ANSI_C_QUOTE="0" && ansi_c_quote_prefix_at "$line" "$index" && COMMENT_PARSER_IN_ANSI_C_QUOTE="1"
  COMMENT_PARSER_IN_SINGLE_QUOTE="$(toggle_flag "$COMMENT_PARSER_IN_SINGLE_QUOTE")"
  [[ "$COMMENT_PARSER_IN_SINGLE_QUOTE" == "0" ]] && COMMENT_PARSER_IN_ANSI_C_QUOTE="0"
  return 0
}

comment_parser_escape_starts() {
  [[ "${1:-}" == "\\" ]] || return 1
  [[ "${2:-0}" == "0" || "${3:-0}" == "1" ]]
}

comment_escape_starts() {
  [[ "${1:-}" == "\\" ]] || return 1
  [[ "${2:-}" == "0" ]]
}

single_quote_opens() {
  [[ "${1:-}" == "'" ]] || return 1
  [[ "${2:-}" == "0" ]]
}

double_quote_opens() {
  [[ "${1:-}" == '"' ]] || return 1
  [[ "${2:-}" == "0" ]]
}

shell_comment_at() {
  local line="${1:-}"
  local index="${2:-0}"
  local char="${3:-}"
  local in_single="${4:-0}"
  local in_double="${5:-0}"
  shell_comment_starts_at "$line" "$index" "$char" "$in_single" "$in_double" || return 1
  printf '%s\n' "$index"
}

shell_comment_starts_at() {
  local line="${1:-}"
  local index="${2:-0}"
  local char="${3:-}"
  local in_single="${4:-0}"
  local in_double="${5:-0}"
  [[ "$char" == "#" ]] || return 1
  [[ "$in_single$in_double" == "00" ]] || return 1
  comment_start_allowed "$line" "$index"
}

toggle_flag() {
  [[ "${1:-}" == "1" ]] && printf '%s\n' "0" && return
  printf '%s\n' "1"
}

comment_start_allowed() {
  local line="${1:-}"
  local index="${2:-0}"
  local previous
  (( index == 0 )) && return 0
  previous="${line:$((index - 1)):1}"
  [[ "$previous" =~ [[:space:]] ]] && return 0
  comment_starts_after_operator "$previous"
}

comment_starts_after_operator() {
  case "${1:-}" in
    ";"|"|"|"&") return 0 ;;
  esac
  return 1
}

shell_comment_ignored() {
  local index="${1:-0}"
  local body
  body="$(trim "${2:-}")"
  (( index == 0 )) && [[ "$body" == "!"* ]] && return 0
  shell_comment_directive "$body"
}

shell_comment_directive() {
  local body="${1:-}"
  body="$(lowercase "$body")"
  [[ "$body" == shellcheck* ]] && return 0
  [[ "$body" == noqa* ]]
}

comment_allowed() {
  local body
  body="$(trim "${1:-}")"
  comment_matches_any_regex "$body" && return 0
  comment_has_prefix_identifier "$body" && return 0
  comment_has_suffix_identifier "$body"
}

comment_matches_any_regex() {
  local body="${1:-}"
  local matcher
  [[ "${#COMMENT_MATCHERS[@]}" -gt 0 ]] || return 1
  for matcher in "${COMMENT_MATCHERS[@]}"; do
    comment_matches_regex "$body" "$matcher" && return 0
  done
  return 1
}

comment_matches_regex() {
  local body="${1:-}"
  local matcher
  local normalized_body normalized_matcher
  matcher="$(trim "${2:-}")"
  [[ -n "$matcher" ]] || return 1
  normalized_body="$(lowercase "$body")"
  normalized_matcher="$(lowercase "$matcher")"
  [[ "$normalized_body" =~ $normalized_matcher ]]
}

comment_has_prefix_identifier() {
  local body="${1:-}"
  local identifier
  [[ "${#COMMENT_PREFIX_IDENTIFIERS[@]}" -gt 0 ]] || return 1
  for identifier in "${COMMENT_PREFIX_IDENTIFIERS[@]}"; do
    comment_prefix_matches "$body" "$identifier" && return 0
  done
  return 1
}

comment_prefix_matches() {
  local body identifier remainder
  body="$(trim "${1:-}")"
  identifier="$(trim "${2:-}")"
  [[ -n "$identifier" ]] || return 1
  body="$(lowercase "$body")"
  identifier="$(lowercase "$identifier")"
  [[ "$body" == "$identifier"* ]] || return 1
  identifier_ends_word "$identifier" || return 0
  remainder="${body:${#identifier}:1}"
  identifier_boundary_char "$remainder"
}

comment_has_suffix_identifier() {
  local body="${1:-}"
  local identifier
  [[ "${#COMMENT_SUFFIX_IDENTIFIERS[@]}" -gt 0 ]] || return 1
  for identifier in "${COMMENT_SUFFIX_IDENTIFIERS[@]}"; do
    comment_suffix_matches "$body" "$identifier" && return 0
  done
  return 1
}

comment_suffix_matches() {
  local body identifier offset previous
  body="$(trim "${1:-}")"
  identifier="$(trim "${2:-}")"
  [[ -n "$identifier" ]] || return 1
  body="$(lowercase "$body")"
  identifier="$(lowercase "$identifier")"
  [[ "$body" == *"$identifier" ]] || return 1
  offset=$((${#body} - ${#identifier}))
  (( offset == 0 )) && return 0
  previous="${body:$((offset - 1)):1}"
  identifier_boundary_char "$previous"
}

identifier_ends_word() {
  local value="${1:-}"
  local last
  last="${value:$((${#value} - 1)):1}"
  [[ "$last" =~ [A-Za-z0-9_] ]]
}

identifier_boundary_char() {
  local char="${1:-}"
  [[ -z "$char" ]] && return 0
  [[ ! "$char" =~ [A-Za-z0-9_] ]]
}

condition_text() {
  local line="${1:-}"
  line="${line#if }"
  line="${line#elif }"
  line="${line#while }"
  line="${line#until }"
  line="${line%; then*}"
  line="${line%; do*}"
  printf '%s\n' "$line"
}

count_condition_operators() {
  local text="${1:-}"
  local count="0"
  count=$((count + $(count_occurrences "$text" "&&")))
  count=$((count + $(count_occurrences "$text" "||")))
  count=$((count + $(count_occurrences " $text " " -a ")))
  count=$((count + $(count_occurrences " $text " " -o ")))
  count=$((count + $(count_occurrences " $text " " ! ")))
  printf '%s\n' "$count"
}

count_expression_operators() {
  local line="${1:-}"
  local pipe_line count
  pipe_line="${line//||/}"
  pipe_line="${pipe_line//|&/}"
  count="0"
  count=$((count + $(count_occurrences "$line" "&&")))
  count=$((count + $(count_occurrences "$line" "||")))
  count=$((count + $(count_occurrences "$pipe_line" "|")))
  printf '%s\n' "$count"
}

line_starts_control() {
  local line="${1:-}"
  local word
  word="$(first_word "$line")"
  control_word "$word"
}

control_word() {
  case "${1:-}" in
    if) return 0 ;;
    elif) return 0 ;;
    while) return 0 ;;
    until) return 0 ;;
    for) return 0 ;;
    case) return 0 ;;
    else) return 0 ;;
    fi) return 0 ;;
    done) return 0 ;;
    "esac") return 0 ;;
  esac
  return 1
}

comparison_left_name() {
  local line="${1:-}"
  local condition
  condition="$(condition_text "$line")"
  comparison_left_name_from_condition "$condition"
}

comparison_left_name_from_condition() {
  local condition="${1:-}"
  local opener left operator
  read -r opener left operator _ <<< "$condition"
  comparison_opener_supported "$opener" || return
  comparison_operator_supported "$operator" || return
  printf '%s\n' "$left"
}

comparison_opener_supported() {
  case "${1:-}" in
    "[[") return 0 ;;
    "[") return 0 ;;
    "test") return 0 ;;
  esac
  return 1
}

comparison_operator_supported() {
  case "${1:-}" in
    "==") return 0 ;;
    "=") return 0 ;;
    "-eq") return 0 ;;
    "-ne") return 0 ;;
    "-lt") return 0 ;;
    "-le") return 0 ;;
    "-gt") return 0 ;;
    "-ge") return 0 ;;
  esac
  return 1
}

track_if_chain_comparison() {
  local path="${1:-$SCAN_PATH}"
  local line_number="${2:-$SCAN_LINE_NUMBER}"
  local line="${3:-$CURRENT_LINE_TEXT}"
  (( IF_DEPTH > 0 )) || return
  update_if_chain_count "$path" "$line_number" "$line"
}

update_if_chain_count() {
  local path="${1:-}"
  local line_number="${2:-}"
  local line="${3:-}"
  local next_name current_name
  next_name="$(comparison_left_name "$line")"
  current_name="${IF_COMPARE_NAME[$IF_DEPTH]}"
  [[ -z "$next_name" ]] && return
  [[ "$next_name" != "$current_name" ]] && return
  IF_COMPARE_COUNT[IF_DEPTH]=$((IF_COMPARE_COUNT[IF_DEPTH] + 1))
  maybe_report_if_chain "$path" "$line_number"
}

maybe_report_if_chain() {
  local path="${1:-}"
  local line_number="${2:-}"
  local count
  count="${IF_COMPARE_COUNT[$IF_DEPTH]}"
  (( count < MIN_CASE_CHAIN_LENGTH )) && return
  [[ "${IF_COMPARE_REPORTED[$IF_DEPTH]}" == "1" ]] && return
  report_if_chain "$path" "$line_number" "$count"
}

report_if_chain() {
  local path="${1:-}"
  local line_number="${2:-}"
  local count="${3:-}"
  local name message
  name="${IF_COMPARE_NAME[$IF_DEPTH]}"
  message="If chain compares $name $count times. Prefer a case statement."
  add_diag "$path" "$line_number" "1" "LEG034" "$message"
  IF_COMPARE_REPORTED[IF_DEPTH]="1"
}

direct_entry_from_line() {
  local line="${1:-}"
  local word
  for word in $line; do
    direct_entry_word "$word" && return
  done
}

direct_entry_word() {
  local word="${1:-}"
  [[ "$word" == -* ]] && return 1
  [[ "${#DIRECT_SHELL_ENTRY_PATTERNS[@]}" -gt 0 ]] || return 1
  path_matches_any "$word" "${DIRECT_SHELL_ENTRY_PATTERNS[@]}" || return 1
  printf '%s\n' "$word"
}

file_has_allowed_shebang() {
  local path="${1:-}"
  local first_line
  first_line="$(sed -n '1p' "$path" 2>/dev/null)"
  [[ "$first_line" == "#!"* ]] || return 1
  shell_runtime_allowed "${first_line#\#!}"
}

path_parent_depth() {
  local path="${1:-}"
  local normalized
  normalized="${path#./}"
  awk -F/ '{print NF-1}' <<< "$normalized"
}

filename_without_extension() {
  local path="${1:-}"
  local file
  file="$(basename "$path")"
  printf '%s\n' "${file%.*}"
}

filename_base() {
  local path="${1:-}"
  local name
  name="$(basename "$path")"
  name="${name#\.}"
  printf '%s\n' "${name%%.*}"
}

filename_base_allowed() {
  local base="${1:-}"
  local parent="${2:-}"
  [[ "$base" == "$parent" ]] && return 0
  filename_base_standalone "$base"
}

filename_base_standalone() {
  case "${1:-}" in
    index|constants|helpers|utils) return 0 ;;
  esac
  return 1
}

filename_casing_mixed() {
  local name="${1:-}"
  local has_hyphen has_underscore has_upper has_lower
  [[ "$name" == *-* ]] && has_hyphen="1" || has_hyphen="0"
  [[ "$name" == *_* ]] && has_underscore="1" || has_underscore="0"
  [[ "$name" =~ [A-Z] ]] && has_upper="1" || has_upper="0"
  [[ "$name" =~ [a-z] ]] && has_lower="1" || has_lower="0"
  filename_casing_flags_mixed "$has_hyphen" "$has_underscore" "$has_upper" "$has_lower"
}

filename_casing_flags_mixed() {
  local has_hyphen="${1:-}"
  local has_underscore="${2:-}"
  local has_upper="${3:-}"
  local has_lower="${4:-}"
  casing_mixes_separators "$has_hyphen" "$has_underscore" && return 0
  casing_mixes_separator_with_case "$has_hyphen" "$has_underscore" "$has_upper" "$has_lower"
}

casing_mixes_separators() {
  local has_hyphen="${1:-}"
  local has_underscore="${2:-}"
  [[ "$has_hyphen" == "1" ]] || return 1
  [[ "$has_underscore" == "1" ]]
}

casing_mixes_separator_with_case() {
  local has_hyphen="${1:-}"
  local has_underscore="${2:-}"
  local has_upper="${3:-}"
  local has_lower="${4:-}"
  [[ "$has_upper" == "1" ]] || return 1
  [[ "$has_lower" == "1" ]] || return 1
  [[ "$has_hyphen$has_underscore" != "00" ]]
}

has_bool_literal_arg() {
  local line="${1:-}"
  line_contains_word "$line" "true" && return 0
  line_contains_word "$line" "false"
}

line_contains_word() {
  local line="${1:-}"
  local word="${2:-}"
  local padded
  padded=" $line "
  [[ "$padded" == *" $word "* ]]
}

add_diag() {
  local path="${1:-}"
  local line="${2:-}"
  local column="${3:-}"
  local code="${4:-}"
  local message="${5:-}"
  rule_enabled "$code" || return
  line_ignores_code "$CURRENT_LINE_TEXT" "$code" && return
  append_diag "$path" "$line" "$column" "$code" "$message"
}

append_diag() {
  local path="${1:-}"
  local line="${2:-}"
  local column="${3:-}"
  local code="${4:-}"
  local message="${5:-}"
  DIAG_PATHS+=("$path")
  DIAG_LINES+=("$line")
  DIAG_COLUMNS+=("$column")
  DIAG_CODES+=("$code")
  DIAG_RULES+=("$(rule_name "$code")")
  DIAG_MESSAGES+=("$message")
}
