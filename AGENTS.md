# Agent Rules

Follow established Bash patterns: use ShellCheck for static analysis and shfmt for formatting. No snowflakes; less is more. Prefer the smallest clear change and avoid new architecture or bespoke alternatives.

Do not add code comments unless the human explicitly requests one. For an explicitly requested code comment, prefix its body with `!NOTE:`. Preserve required shebangs and tool directives such as `# shellcheck`.

Run `make check` after shell changes. It runs ShellCheck, shfmt, unit tests, end-to-end tests, and the configured shellcheck-legibility rules.
