#!/usr/bin/env bash
set -euo pipefail

HOOK_MARKER='SHELLCHECK_LEGIBILITY_MANAGED_HOOK=1'

is_ci() {
  [[ "${CI:-}" == "true" || "${CI:-}" == "1" ]]
}

is_git_repo() {
  git rev-parse --show-toplevel > /dev/null 2>&1
}

hooks_dir() {
  git rev-parse --git-path hooks
}

is_unmanaged_hook() {
  local hook_path="${1:?}"
  [[ -e "$hook_path" || -L "$hook_path" ]] || return 1
  ! grep -Fq "$HOOK_MARKER" "$hook_path"
}

write_hook() {
  local hook_path="${1:?}"
  cat > "$hook_path" << 'EOF'
#!/bin/sh
SHELLCHECK_LEGIBILITY_MANAGED_HOOK=1
exec make pre-commit
EOF
  chmod +x "$hook_path"
}

install_hook() {
  local hook_directory hook_path
  hook_directory="$(hooks_dir)"
  mkdir -p "$hook_directory"
  hook_path="$hook_directory/pre-commit"
  if is_unmanaged_hook "$hook_path"; then
    printf 'Skipping existing unmanaged hook: %s\n' "$hook_path"
    return 0
  fi
  write_hook "$hook_path"
  printf 'Installed pre-commit hook: %s\n' "$hook_path"
}

main() {
  if is_ci; then
    printf 'CI environment detected, skipping git hooks installation\n'
    return 0
  fi
  if is_git_repo; then
    install_hook
    return 0
  fi
  printf 'Not a git repository, skipping git hooks installation\n'
}

main "$@"
