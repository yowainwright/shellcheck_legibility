# Contributing

## Development

Install Go 1.26 or later, Bash, ShellCheck, and shfmt. Docker is needed for end-to-end tests.

```sh
make build
make unit
make integration
make e2e
```

`make check` runs all tests, formatting, ShellCheck, system Bash compatibility, and the linter against this repository. `make benchmark` measures uncached and cached scans with Hyperfine.

## Layout

| Path | Responsibility |
| --- | --- |
| `cmd/shellcheck-legibility/` | Entry point, arguments, configuration, file discovery, and cache. |
| `internal/lint/` | Native parsing, rules, and diagnostics. No filesystem access. |
| `internal/bash/` | Embedded compatibility scanner for incomplete or unsupported shell syntax. |
| `tests/integration/` | Compiled CLI behavior, engine parity, caching, and staged-file hooks. |
| `tests/e2e/` | Packaged binary installation and checks in Docker. |
| `scripts/` | Release packaging and hook setup. |

Go unit tests live beside their implementation as `*_test.go`, with shell snippets and expected diagnostics in the test itself. The Bash compatibility tests retain their configuration fixtures in `internal/bash/testdata/`.

`make build` writes `bin/shellcheck-legibility`. Both `bin/` and `.build/` are ignored build output. Rebuild after changing Go or embedded Bash source. Installed releases do not require Go; compatibility scanning requires Bash.

## Changing a rule

Add a focused case to `internal/lint/rules_test.go` or `comments_test.go`, then update the rule implementation. Parser and diagnostic behavior belongs in `lint_test.go`. Use an inline shell snippet and assert the rule code, location, and message; include a nearby example that should pass.

Keep the Bash compatibility rule consistent with the native rule. Add CLI coverage in `tests/integration/cli_test.go` when changing fallback behavior or introducing a rule. That suite compares both engines for every rule and checks that incomplete source still produces feedback without executing it.

For a focused iteration:

```sh
go test ./internal/lint -run TestBoolArgumentStillReported
make unit
make integration
```

Update the README rule example when diagnostics or defaults change. Run `make check` before submitting.

## Code Style

Keep checks syntax-oriented unless a rule explicitly needs more context. Prefer small helpers, early returns, named intermediate values, and rule functions named after the lint checks they implement.

## Pull Requests

Open focused pull requests with tests for new or changed rules. Include a short before-and-after shell example when changing diagnostics, defaults, or configuration.
