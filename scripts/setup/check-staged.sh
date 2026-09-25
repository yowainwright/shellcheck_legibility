#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGE_DIR=""
STAGED_PATHS=()
STAGED_FILES=()
STAGED_MODE=""
STAGED_OID=""
STAGED_STAGE=""

collect_staged_paths() {
  local file
  while IFS= read -r -d '' file; do
    STAGED_PATHS+=("$file")
  done < <(git diff --cached --name-only --diff-filter=ACMR -z)
}

load_staged_entry() {
  local file="${1:-}"
  local metadata
  metadata="$(git --literal-pathspecs ls-files --format='%(objectmode) %(objectname) %(stage)' -- "$file")"
  [[ -n "$metadata" ]] || return 1
  [[ "$metadata" != *$'\n'* ]] || return 1
  read -r STAGED_MODE STAGED_OID STAGED_STAGE <<< "$metadata"
  [[ "$STAGED_STAGE" == "0" ]]
}

materialize_staged_file() {
  local file="${1:-}"
  local target
  load_staged_entry "$file" || return 1
  case "$STAGED_MODE" in
    100644 | 100755) ;;
    *) return 0 ;;
  esac
  target="$STAGE_DIR/$file"
  mkdir -p -- "$(dirname "$target")"
  git cat-file blob "$STAGED_OID" > "$target"
  [[ "$STAGED_MODE" == "100755" ]] && chmod +x "$target"
  STAGED_FILES+=("./$file")
}

materialize_staged_files() {
  local file
  for file in "${STAGED_PATHS[@]}"; do
    materialize_staged_file "$file"
  done
}

cleanup_stage() {
  [[ -z "$STAGE_DIR" ]] || rm -rf -- "$STAGE_DIR"
}

main() {
  cd "$ROOT_DIR"
  collect_staged_paths
  [[ "${#STAGED_PATHS[@]}" -gt 0 ]] || return 0
  STAGE_DIR="$(mktemp -d "$ROOT_DIR/.shellcheck-legibility-stage.XXXXXX")"
  trap cleanup_stage EXIT
  materialize_staged_files
  [[ "${#STAGED_FILES[@]}" -gt 0 ]] || return 0
  cd "$STAGE_DIR"
  "$ROOT_DIR/bin/shellcheck-legibility" check "${STAGED_FILES[@]}"
}

main "$@"
