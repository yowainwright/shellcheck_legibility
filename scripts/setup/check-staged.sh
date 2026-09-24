#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGED_FILES=()
HAS_STAGED_FILES="0"

collect_staged_files() {
  local file
  while IFS= read -r -d '' file; do
    STAGED_FILES+=("./$file")
    HAS_STAGED_FILES="1"
  done < <(git diff --cached --name-only --diff-filter=ACMR -z)
}

main() {
  cd "$ROOT_DIR"
  collect_staged_files
  [[ "$HAS_STAGED_FILES" == "1" ]] || return 0
  "$ROOT_DIR/bin/shellcheck-legibility" check "${STAGED_FILES[@]}"
}

main "$@"
