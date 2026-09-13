LIST_ITEM=""
LIST_IN_SINGLE_QUOTE="0"
LIST_IN_DOUBLE_QUOTE="0"
PARSED_LIST=()
YAML_DECODED_ESCAPE=""
YAML_ESCAPE_WIDTH="0"

trim() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

lowercase() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

strip_comment() {
  local line="${1:-}"
  printf '%s\n' "${line%%#*}"
}

clean_scalar() {
  local value="${1:-}"
  value="$(trim "$value")"
  value="${value//\"/}"
  value="${value//\'/}"
  printf '%s\n' "$value"
}

csv_to_array() {
  local raw="${1:-}"
  local value index
  PARSED_LIST=()
  reset_list_parser
  value="$(trim "$raw")"
  value="${value#[}"
  value="${value%]}"
  for ((index = 0; index < ${#value}; index++)); do
    consume_list_value_character "$value" "$index"
    index=$((index + YAML_ESCAPE_WIDTH))
  done
  append_list_item
}

reset_list_parser() {
  LIST_ITEM=""
  LIST_IN_SINGLE_QUOTE="0"
  LIST_IN_DOUBLE_QUOTE="0"
}

consume_list_value_character() {
  local value="${1:-}"
  local index="${2:-0}"
  YAML_ESCAPE_WIDTH="0"
  consume_list_escape "$value" "$index" && return
  consume_list_character "${value:index:1}"
}

consume_list_character() {
  local char="${1:-}"
  list_single_quote_toggles "$char" && return
  list_double_quote_toggles "$char" && return
  list_separator_consumed "$char" && return
  LIST_ITEM+="$char"
}

consume_list_escape() {
  local value="${1:-}"
  local index="${2:-0}"
  local escape_start
  [[ "${value:index:1}" == "\\" ]] || return 1
  [[ "$LIST_IN_DOUBLE_QUOTE" == "1" ]] || return 1
  escape_start=$((index + 1))
  decode_yaml_escape "${value:escape_start}"
  LIST_ITEM+="$YAML_DECODED_ESCAPE"
}

decode_yaml_double_quoted() {
  local value="${1:-}"
  local index char escape_start result=""
  for ((index = 0; index < ${#value}; index++)); do
    char="${value:index:1}"
    [[ "$char" == "\\" ]] || { result+="$char"; continue; }
    escape_start=$((index + 1))
    decode_yaml_escape "${value:escape_start}"
    result+="$YAML_DECODED_ESCAPE"
    index=$((index + YAML_ESCAPE_WIDTH))
  done
  printf '%s\n' "$result"
}

decode_yaml_escape() {
  local value="${1:-}"
  local char="${value:0:1}"
  YAML_ESCAPE_WIDTH="1"
  [[ -n "$char" ]] || { YAML_DECODED_ESCAPE="\\"; YAML_ESCAPE_WIDTH="0"; return; }
  case "$char" in
    x) decode_yaml_hex_escape x "${value:1:2}" 2 ;;
    u) decode_yaml_hex_escape u "${value:1:4}" 4 ;;
    U) decode_yaml_hex_escape U "${value:1:8}" 8 ;;
    *) set_yaml_decoded_escape "$char" ;;
  esac
}

decode_yaml_hex_escape() {
  local marker="${1:-}"
  local digits="${2:-}"
  local width="${3:-0}"
  if [[ "${#digits}" -eq "$width" && "$digits" =~ ^[[:xdigit:]]+$ ]]; then
    set_yaml_unicode_escape "$digits"
    YAML_ESCAPE_WIDTH=$((width + 1))
    return
  fi
  YAML_DECODED_ESCAPE="\\$marker"
}

set_yaml_decoded_escape() {
  local char="${1:-}"
  set_yaml_control_escape "$char" && return
  set_yaml_symbol_escape "$char" && return
  YAML_DECODED_ESCAPE="\\$char"
}

set_yaml_control_escape() {
  case "${1:-}" in
    0) YAML_DECODED_ESCAPE="\\0" ;;
    a) YAML_DECODED_ESCAPE=$'\a' ;;
    b) YAML_DECODED_ESCAPE=$'\b' ;;
    t) YAML_DECODED_ESCAPE=$'\t' ;;
    n) YAML_DECODED_ESCAPE=$'\n' ;;
    v) YAML_DECODED_ESCAPE=$'\v' ;;
    f) YAML_DECODED_ESCAPE=$'\f' ;;
    r) YAML_DECODED_ESCAPE=$'\r' ;;
    e) YAML_DECODED_ESCAPE=$'\e' ;;
    *) return 1 ;;
  esac
}

set_yaml_symbol_escape() {
  case "${1:-}" in
    ' ') YAML_DECODED_ESCAPE=' ' ;;
    '"') YAML_DECODED_ESCAPE='"' ;;
    /) YAML_DECODED_ESCAPE='/' ;;
    "\\") YAML_DECODED_ESCAPE="\\" ;;
    N) set_yaml_unicode_escape 0085 ;;
    _) set_yaml_unicode_escape 00a0 ;;
    L) set_yaml_unicode_escape 2028 ;;
    P) set_yaml_unicode_escape 2029 ;;
    *) return 1 ;;
  esac
}

set_yaml_unicode_escape() {
  local digits="${1:-}"
  local codepoint
  codepoint=$((16#$digits))
  if [[ "$codepoint" -le 127 ]]; then
    set_yaml_utf8_bytes "$codepoint"
    return
  fi
  if [[ "$codepoint" -le 2047 ]]; then
    set_yaml_utf8_bytes "$((192 + codepoint / 64))" "$((128 + codepoint % 64))"
    return
  fi
  if [[ "$codepoint" -le 65535 ]]; then
    set_yaml_utf8_bytes "$((224 + codepoint / 4096))" "$((128 + (codepoint / 64) % 64))" "$((128 + codepoint % 64))"
    return
  fi
  if [[ "$codepoint" -le 1114111 ]]; then
    set_yaml_utf8_bytes "$((240 + codepoint / 262144))" "$((128 + (codepoint / 4096) % 64))" "$((128 + (codepoint / 64) % 64))" "$((128 + codepoint % 64))"
    return
  fi
  YAML_DECODED_ESCAPE="\\u$digits"
}

set_yaml_utf8_bytes() {
  local byte escaped=""
  for byte in "$@"; do
    printf -v byte '%03o' "$byte"
    escaped="${escaped}\\${byte}"
  done
  printf -v YAML_DECODED_ESCAPE '%b' "$escaped"
}

list_single_quote_toggles() {
  [[ "${1:-}" == "'" ]] || return 1
  [[ "$LIST_IN_DOUBLE_QUOTE" == "0" ]] || return 1
  LIST_IN_SINGLE_QUOTE=$((1 - LIST_IN_SINGLE_QUOTE))
}

list_double_quote_toggles() {
  [[ "${1:-}" == '"' ]] || return 1
  [[ "$LIST_IN_SINGLE_QUOTE" == "0" ]] || return 1
  LIST_IN_DOUBLE_QUOTE=$((1 - LIST_IN_DOUBLE_QUOTE))
}

list_separator_consumed() {
  [[ "${1:-}" == "," ]] || return 1
  [[ "$LIST_IN_SINGLE_QUOTE$LIST_IN_DOUBLE_QUOTE" == "00" ]] || return 1
  append_list_item
}

append_list_item() {
  local value
  value="$(trim "$LIST_ITEM")"
  LIST_ITEM=""
  [[ -z "$value" ]] && return
  PARSED_LIST+=("$value")
}

count_occurrences() {
  local text="${1:-}"
  local needle="${2:-}"
  local count="0"
  while [[ "$text" == *"$needle"* ]]; do
    text="${text#*"$needle"}"
    count=$((count + 1))
  done
  printf '%s\n' "$count"
}

json_escape() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '%s\n' "$value"
}

first_word() {
  local line="${1:-}"
  local first
  read -r first _ <<< "$line"
  printf '%s\n' "$first"
}

path_matches_any() {
  local path="${1:-}"
  local pattern
  shift
  path="${path#./}"
  for pattern in "$@"; do
    # shellcheck disable=SC2053
    [[ "$path" == $pattern ]] && return 0
  done
  return 1
}
