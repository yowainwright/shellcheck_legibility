expand_targets() {
  if [[ "${#TARGETS[@]}" -eq 0 ]]; then
    TARGETS+=(".")
  fi

  local target
  for target in "${TARGETS[@]}"; do
    expand_target "$target"
  done
}

expand_target() {
  local target="${1:-}"
  [[ -d "$target" ]] || add_target_file "$target"
  [[ -d "$target" ]] || return
  expand_directory "$target"
}

add_target_file() {
  local target="${1:-}"
  is_shell_file "$target" && FILES+=("$target")
}

expand_directory() {
  local dir="${1:-}"
  local file
  while IFS= read -r -d '' file; do
    add_shell_file "$file"
  done < <(find "$dir" -type f -print0)
}

add_shell_file() {
  local file="${1:-}"
  path_excluded "$file" && return
  is_shell_file "$file" && FILES+=("$file")
}

path_excluded() {
  local path="${1:-}"
  local item
  for item in "${EXCLUDE[@]}"; do
    path_matches_exclude "$path" "$item" && return 0
  done
  return 1
}

path_matches_exclude() {
  local path="${1:-}"
  local item="${2:-}"
  [[ "$path" == "$item" ]] && return 0
  [[ "$path" == ./"$item"/* ]] && return 0
  [[ "$path" == *"/$item/"* ]]
}

is_shell_file() {
  local path="${1:-}"
  shell_extension "$path" && return 0
  shell_shebang "$path"
}

shell_extension() {
  case "${1:-}" in
    *.sh | *.bash | *.zsh | *.ksh) return 0 ;;
  esac
  return 1
}

shell_shebang() {
  local path="${1:-}"
  local first_line
  first_line="$(sed -n '1p' "$path" 2> /dev/null)"
  [[ "$first_line" == "#!"* ]] || return 1
  shell_runtime_allowed "${first_line#\#!}"
}

shell_runtime_allowed() {
  local command="${1:-}"
  local runtime
  command="$(shell_runtime_name "$command")"
  for runtime in "${EXECUTABLE_RUNTIMES[@]}"; do
    [[ "$command" == "$runtime" ]] && return 0
  done
  return 1
}

shell_runtime_name() {
  local command="${1:-}"
  command="$(trim "$command")"
  command="${command#/usr/bin/env }"
  printf '%s\n' "$(basename -- "$command")"
}
