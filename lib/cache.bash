# shellcheck shell=bash

CACHE_DIR="${SHELLCHECK_LEGIBILITY_CACHE_DIR:-}"
CACHE_SOURCES=("${BASH_SOURCE[0]}")
CACHE_HASH_COMMAND=()
CACHE_CONTEXT=""
CACHE_RECORDS=()

prepare_cache() {
  CACHE_CONTEXT=""
  [[ -n "$CACHE_DIR" ]] || return 0
  select_cache_hash_command || return 0
  (
    umask 077
    mkdir -p "$CACHE_DIR"
  ) 2> /dev/null || return 0
  CACHE_CONTEXT="$(cache_context | cache_digest)" || CACHE_CONTEXT=""
}

select_cache_hash_command() {
  if command -v sha256sum > /dev/null 2>&1; then
    CACHE_HASH_COMMAND=(sha256sum)
  elif command -v shasum > /dev/null 2>&1; then
    CACHE_HASH_COMMAND=(shasum -a 256)
  else
    return 1
  fi
}

cache_digest() {
  local digest
  digest="$("${CACHE_HASH_COMMAND[@]}")" || return 1
  printf '%s' "${digest%% *}"
}

cache_context() {
  printf '%s\0' "cache-v1" "$BASH_VERSION" "${LANG:-}" "${LC_ALL:-}" "${LC_CTYPE:-}" "${LC_COLLATE:-}"
  declare -p SELECT IGNORE EXCLUDE EXECUTABLE_ENTRY_PATTERNS DIRECT_SHELL_ENTRY_PATTERNS EXECUTABLE_RUNTIMES
  declare -p COMMENT_MATCHERS COMMENT_PREFIX_IDENTIFIERS COMMENT_SUFFIX_IDENTIFIERS AUTOMATED_COMMENT_IDENTIFIERS
  declare -p MAX_EXPRESSION_OPERATORS MAX_CONDITION_OPERATORS MAX_CONTROL_FLOW_DEPTH MAX_FUNCTION_LINES
  declare -p MIN_CASE_CHAIN_LENGTH MIN_DIRNAME_MATCH_DEPTH MIN_OBJECT_LOOKUP_CHAIN_LENGTH
  cat "${CACHE_SOURCES[@]}"
}

cache_file_key() {
  local path="${1:-}"
  [[ -f "$path" && -r "$path" ]] || return 1
  {
    printf '%s\0' "$CACHE_CONTEXT" "$PWD" "$path"
    if [[ -x "$path" ]]; then printf 'executable\0'; else printf 'regular\0'; fi
    cat "$path"
  } | cache_digest
}

lint_file_with_cache() {
  local path="${1:-}"
  local key="" start="${#DIAG_CODES[@]}"
  if [[ -n "$CACHE_CONTEXT" ]]; then
    key="$(cache_file_key "$path")" || key=""
  fi
  restore_cached_file "$path" "$key" && return
  lint_file "$path"
  [[ -n "$key" ]] || return 0
  [[ "$(cache_file_key "$path")" == "$key" ]] || return 0
  save_cached_diagnostics "$key" "$start" 2> /dev/null
}

restore_cached_file() {
  local path="${1:-}" key="${2:-}"
  [[ -n "$key" ]] || return 1
  read_cached_diagnostics "$CACHE_DIR/$key" 2> /dev/null || return 1
  replay_cached_diagnostics "$path"
}

read_cached_diagnostics() {
  local entry="${1:-}"
  [[ -f "$entry" && -r "$entry" ]] || return 1
  read_cache_records < "$entry" || return 1
  validate_cache_records
}

read_cache_records() {
  local field=""
  CACHE_RECORDS=()
  while IFS= read -r -d '' field; do
    CACHE_RECORDS+=("$field")
  done
  [[ -z "$field" ]]
}

validate_cache_records() {
  local count="${#CACHE_RECORDS[@]}" index
  [[ "$count" -ge 2 ]] || return 1
  [[ "${CACHE_RECORDS[0]}" == "cache-v1" ]] || return 1
  [[ "${CACHE_RECORDS[count - 1]}" == "end" ]] || return 1
  [[ "$(((count - 2) % 5))" -eq 0 ]] || return 1
  for ((index = 1; index < count - 1; index += 5)); do
    [[ "${CACHE_RECORDS[index]}" =~ ^[1-9][0-9]*$ ]] || return 1
    [[ "${CACHE_RECORDS[index + 1]}" =~ ^[1-9][0-9]*$ ]] || return 1
    [[ "${CACHE_RECORDS[index + 2]}" =~ ^LEG[0-9][0-9][0-9]$ ]] || return 1
  done
}

replay_cached_diagnostics() {
  local path="${1:-}" index
  for ((index = 1; index < ${#CACHE_RECORDS[@]} - 1; index += 5)); do
    DIAG_PATHS+=("$path")
    DIAG_LINES+=("${CACHE_RECORDS[index]}")
    DIAG_COLUMNS+=("${CACHE_RECORDS[index + 1]}")
    DIAG_CODES+=("${CACHE_RECORDS[index + 2]}")
    DIAG_RULES+=("${CACHE_RECORDS[index + 3]}")
    DIAG_MESSAGES+=("${CACHE_RECORDS[index + 4]}")
  done
}

save_cached_diagnostics() {
  local key="${1:-}" start="${2:-}"
  local entry
  entry="$(mktemp "$CACHE_DIR/.pending.XXXXXX" 2> /dev/null)" || return 0
  write_cache_records "$start" > "$entry" && mv -f "$entry" "$CACHE_DIR/$key"
  rm -f "$entry"
}

write_cache_records() {
  local index="${1:-}"
  printf 'cache-v1\0'
  for (( ; index < ${#DIAG_CODES[@]}; index++)); do
    printf '%s\0' "${DIAG_LINES[index]}" "${DIAG_COLUMNS[index]}" \
      "${DIAG_CODES[index]}" "${DIAG_RULES[index]}" "${DIAG_MESSAGES[index]}" || return 1
  done
  printf 'end\0'
}
