write_diagnostics() {
  [[ "$OUTPUT_FORMAT" == "json" ]] && write_json_diagnostics
  [[ "$OUTPUT_FORMAT" == "json" ]] && return
  write_text_diagnostics
}

write_text_diagnostics() {
  local index
  for index in "${!DIAG_CODES[@]}"; do
    write_text_diagnostic "$index"
  done
}

write_text_diagnostic() {
  local index="${1:-}"
  printf '%s:%s:%s: %s %s\n' \
    "${DIAG_PATHS[$index]}" \
    "${DIAG_LINES[$index]}" \
    "${DIAG_COLUMNS[$index]}" \
    "${DIAG_CODES[$index]}" \
    "${DIAG_MESSAGES[$index]}"
}

write_json_diagnostics() {
  local index separator
  printf '[\n'
  separator=""
  for index in "${!DIAG_CODES[@]}"; do
    write_json_diagnostic "$index" "$separator"
    separator=$',\n'
  done
  printf '\n]\n'
}

write_json_diagnostic() {
  local index="${1:-}"
  local separator="${2:-}"
  printf '%s  {' "$separator"
  write_json_fields "$index"
  printf '}'
}

write_json_fields() {
  local index="${1:-}"
  local path rule message
  json_escape_into path "${DIAG_PATHS[$index]}"
  json_escape_into rule "${DIAG_RULES[$index]}"
  json_escape_into message "${DIAG_MESSAGES[$index]}"
  printf '"path":"%s",' "$path"
  printf '"line":%s,' "${DIAG_LINES[$index]}"
  printf '"column":%s,' "${DIAG_COLUMNS[$index]}"
  printf '"code":"%s",' "${DIAG_CODES[$index]}"
  printf '"rule":"%s",' "$rule"
  printf '"message":"%s"' "$message"
}
