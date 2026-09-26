# shellcheck-legibility

<!-- badges derived from .github/workflows, GitHub tags, and LICENSE -->
[![CI][ci-badge]][ci-workflow]
[![Homebrew][homebrew-badge]][homebrew-workflow]
[![Version][version-badge]][tags]
[![License][license-badge]][license]

[ci-badge]: https://github.com/yowainwright/shellcheck_legibility/actions/workflows/ci.yml/badge.svg
[ci-workflow]: https://github.com/yowainwright/shellcheck_legibility/actions/workflows/ci.yml
[homebrew-badge]: https://github.com/yowainwright/shellcheck_legibility/actions/workflows/homebrew.yml/badge.svg
[homebrew-workflow]: https://github.com/yowainwright/shellcheck_legibility/actions/workflows/homebrew.yml
[version-badge]: https://img.shields.io/github/v/tag/yowainwright/shellcheck_legibility
[tags]: https://github.com/yowainwright/shellcheck_legibility/tags
[license-badge]: https://img.shields.io/github/license/yowainwright/shellcheck_legibility
[license]: https://github.com/yowainwright/shellcheck_legibility/blob/main/LICENSE

`shellcheck-legibility` makes shell scripts easier to review. It works best alongside [ShellCheck](https://github.com/koalaman/shellcheck) (correctness, portability, quoting, and semantics) and [shfmt](https://github.com/mvdan/sh#shfmt) (formatting).

Releases ship a native Go engine using [mvdan's shell parser](https://github.com/mvdan/sh). Set `SHELLCHECK_LEGIBILITY_ENGINE=bash` to use the Bash compatibility engine instead – that mode requires Bash. ShellCheck is a dev lint dependency, not a runtime one.

## Install

```sh
brew tap yowainwright/tap
brew install yowainwright/tap/shellcheck-legibility
```

## Agent sessions

Turn on the cache in the shell that boots your agent. Existing lint hooks just pick it up automatically:

```sh
export SHELLCHECK_LEGIBILITY_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/shellcheck-legibility"
```

Unchanged files replay their diagnostics and exit status. File content, rule settings, paths, and engine changes all invalidate cached results. Editing a file replaces its cache entry. Changing settings or the engine creates a separate entry. Cache entries hold data only – never executable shell code. If caching isn't available, checks still run.

Use `--cache` for individual runs or `--no-cache` for a full rescan. This caches shellcheck-legibility specifically; ShellCheck stays a separate correctness check.

Benchmark uncached vs cached repo checks with `make benchmark` (needs Hyperfine).

## Rules

Only implemented rules are listed here. Each links to its do / don't diff.

<!-- implemented rule codes and names from internal/bash/rules.bash -->

| Code | Rule | Summary |
| --- | --- | --- |
| [`LEG001`](#max-expression-operators-diff) | `max-expression-operators` | Limit `&&`, `||`, and pipeline-heavy shell expressions. |
| [`LEG002`](#hoist-if-operators-diff) | `hoist-if-operators` | Prefer named checks before operator-heavy conditions. |
| [`LEG003`](#max-control-flow-depth-diff) | `max-control-flow-depth` | Limit nested control flow. |
| [`LEG005`](#no-quadratic-patterns-diff) | `no-quadratic-patterns` | Flag nested loops. |
| [`LEG009`](#prefer-early-return-diff) | `prefer-early-return` | Avoid `else` after a branch exits. |
| [`LEG010`](#prefer-guard-clauses-diff) | `prefer-guard-clauses` | Prefer guard clauses inside functions. |
| [`LEG016`](#require-executable-shebang-diff) | `require-executable-shebang` | Require executable shell entries to have a shebang. |
| [`LEG017`](#no-direct-shell-bin-smoke-diff) | `no-direct-shell-bin-smoke` | Prefer installed-command smoke tests over direct shell entry files. |
| [`LEG024`](#prefer-object-lookup-diff) | `prefer-object-lookup` | Prefer `case` or lookup-style flow over repeated equality checks. |
| [`LEG025`](#require-filename-matches-dirname-diff) | `require-filename-matches-dirname` | Require files in named subdirectories to match the directory name. |
| [`LEG026`](#no-mixed-filename-casing-diff) | `no-mixed-filename-casing` | Avoid filenames that mix casing conventions. |
| [`LEG034`](#prefer-case-over-long-if-chain-diff) | `prefer-case-over-long-if-chain` | Prefer `case` over long `elif` chains comparing the same value. |
| [`LEG035`](#no-bool-literal-args-diff) | `no-bool-literal-args` | Avoid boolean literal arguments. |
| [`LEG038`](#max-function-lines-diff) | `max-function-lines` | Keep shell functions within a focused line budget. |
| [`LEG039`](#prefer-functions-diff) | `prefer-functions` | Prefer named functions over top-level script logic. |
| [`LEG040`](#use-defaults-in-functions-diff) | `use-defaults-in-functions` | Use defaulted or guarded positional args in functions. |
| [`LEG041`](#no-unmatched-comments-diff) | `no-unmatched-comments` | Policy opt-in. Reject comments without a configured matcher or identifier. |
| [`LEG042`](#no-automated-comment-attribution-diff) | `no-automated-comment-attribution` | Policy opt-in. Reject explicit automated attribution signatures. |
| [`LEG043`](#no-stacked-comments-diff) | `no-stacked-comments` | Policy opt-in. Reject comments stacked on consecutive lines. |

---

<a id="max-expression-operators"></a>

### `max-expression-operators`

Limit readable operators inside a single command expression.

#### options

- `max-expression-operators`: allowed expression operators. Default: `4`.

<a id="max-expression-operators-diff"></a>

#### do / don't

```diff
- build && test && package && publish && notify
+ build
+ test
+ package
+ publish
+ notify
```

---

<a id="hoist-if-operators"></a>

### `hoist-if-operators`

Prefer a named check before an operator-heavy `if`, `elif`, `while`, or `until` condition. Quoted data and case-pattern separators don't count as shell operators; commands inside substitutions still do.

#### options

- `max-if-operators`: allowed condition operators. Default: `0`.

<a id="hoist-if-operators-diff"></a>

#### do / don't

```diff
- if [[ -n "$user" && -n "$email" ]]; then
+ user_has_contact() {
+   [[ -n "$user" && -n "$email" ]]
+ }
+
+ if user_has_contact; then
    send_invite "$user"
  fi
```

---

<a id="max-control-flow-depth"></a>

### `max-control-flow-depth`

Limit nested branches and loops so the main path stays easy to scan.

#### options

- `max-control-flow-depth`: allowed nested control-flow depth. Default: `3`.

<a id="max-control-flow-depth-diff"></a>

#### do / don't

```diff
- if [[ -n "$repo" ]]; then
-   if git diff --quiet; then
-     if [[ "$target" == "release" ]]; then
-       publish_release
-     fi
-   fi
- fi
+ [[ -n "$repo" ]] || exit 1
+ git diff --quiet || exit 1
+ [[ "$target" == "release" ]] || exit 0
+ publish_release
```

---

<a id="no-quadratic-patterns"></a>

### `no-quadratic-patterns`

Flag nested loops that are likely to become repeated scans.

#### options

None.

<a id="no-quadratic-patterns-diff"></a>

#### do / don't

```diff
- for user in "${users[@]}"; do
-   for owner in "${owners[@]}"; do
-     [[ "$user" == "$owner" ]] && print_owner "$user"
-   done
- done
+ declare -A owner_lookup=()
+ for owner in "${owners[@]}"; do
+   owner_lookup["$owner"]="1"
+ done
+ for user in "${users[@]}"; do
+   [[ -n "${owner_lookup[$user]:-}" ]] && print_owner "$user"
+ done
```

---

<a id="prefer-early-return"></a>

### `prefer-early-return`

Avoid an `else` branch after the previous branch already exits.

#### options

None.

<a id="prefer-early-return-diff"></a>

#### do / don't

```diff
  if [[ -z "$config" ]]; then
    return 1
- else
-   load_config "$config"
  fi
+ load_config "$config"
```

---

<a id="prefer-guard-clauses"></a>

### `prefer-guard-clauses`

Prefer guard clauses over wrapping a whole function body in one branch. Existing guard clauses and optional branches alongside other work are fine.

#### options

None.

<a id="prefer-guard-clauses-diff"></a>

#### do / don't

```diff
  deploy() {
-   if [[ -n "$target" ]]; then
-     build
-     upload "$target"
-   fi
+   [[ -n "$target" ]] || return 1
+   build
+   upload "$target"
  }
```

---

<a id="require-executable-shebang"></a>

### `require-executable-shebang`

Require configured executable entry files to start with an accepted shell shebang.

#### options

- `executable-entry-patterns`: paths treated as executable shell entries.
- `executable-runtimes`: accepted shebang runtimes. Default includes Bash, sh, zsh, and ksh.

<a id="require-executable-shebang-diff"></a>

#### do / don't

```diff
+ #!/usr/bin/env bash
+
  set -u
  main "$@"
```

---

<a id="no-direct-shell-bin-smoke"></a>

### `no-direct-shell-bin-smoke`

Prefer smoke-testing the installed command instead of invoking entry scripts directly with a shell.

#### options

- `direct-shell-entry-patterns`: direct entry paths that shouldn't be shell-invoked in smoke tests.
- `executable-runtimes`: shell runtimes checked in commands.

<a id="no-direct-shell-bin-smoke-diff"></a>

#### do / don't

```diff
- bash bin/shellcheck-legibility --version
+ shellcheck-legibility --version
```

---

<a id="prefer-object-lookup"></a>

### `prefer-object-lookup`

Prefer `case` or lookup-style flow over long repeated equality checks.

#### options

- `min-object-lookup-chain-length`: repeated checks before reporting. Default: `3`.

<a id="prefer-object-lookup-diff"></a>

#### do / don't

```diff
- if [[ "$mode" == "dev" || "$mode" == "test" || "$mode" == "ci" ]]; then
-   enable_debug
- fi
+ case "$mode" in
+   dev|test|ci) enable_debug ;;
+ esac
```

---

<a id="require-filename-matches-dirname"></a>

### `require-filename-matches-dirname`

Require files in named subdirectories to match the directory name.

#### options

- `min-dirname-match-depth`: minimum parent depth before checking. Default: `3`.

<a id="require-filename-matches-dirname-diff"></a>

#### do / don't

```diff
- scripts/deploy/run.sh
+ scripts/deploy/deploy.sh
```

---

<a id="no-mixed-filename-casing"></a>

### `no-mixed-filename-casing`

Avoid filenames that mix casing conventions.

#### options

None.

<a id="no-mixed-filename-casing-diff"></a>

#### do / don't

```diff
- scripts/deployUser.sh
+ scripts/deploy-user.sh
```

---

<a id="prefer-case-over-long-if-chain"></a>

### `prefer-case-over-long-if-chain`

Prefer `case` over long `elif` chains comparing the same value.

#### options

- `min-case-chain-length`: repeated comparisons before reporting. Default: `3`.

<a id="prefer-case-over-long-if-chain-diff"></a>

#### do / don't

```diff
- if [[ "$command" == "build" ]]; then
-   build
- elif [[ "$command" == "test" ]]; then
-   test_all
- elif [[ "$command" == "publish" ]]; then
-   publish
- fi
+ case "$command" in
+   build) build ;;
+   test) test_all ;;
+   publish) publish ;;
+ esac
```

---

<a id="no-bool-literal-args"></a>

### `no-bool-literal-args`

Avoid unquoted boolean literal arguments whose meaning is only clear at the call site. Commands like `true`, `false`, and `command true` are fine, including after `&&` or `||`.

#### options

None.

<a id="no-bool-literal-args-diff"></a>

#### do / don't

```diff
- create_user "$name" true false
+ send_email="true"
+ is_admin="false"
+ create_user "$name" "$send_email" "$is_admin"
```

---

<a id="max-function-lines"></a>

### `max-function-lines`

Keep shell functions within a focused line budget.

#### options

- `max-function-lines`: maximum lines in a function. Default: `20`.

<a id="max-function-lines-diff"></a>

#### do / don't

```diff
  deploy() {
-   validate_env
-   install_dependencies
-   build_assets
-   upload_assets
-   restart_service
-   notify_release
+   prepare_release
+   publish_release
+   notify_release
  }
```

---

<a id="prefer-functions"></a>

### `prefer-functions`

Prefer named functions for script logic and keep top-level code limited to setup and dispatch.

#### options

None.

<a id="prefer-functions-diff"></a>

#### do / don't

```diff
- docker build --tag "$IMAGE_NAME" .
- docker run --rm "$IMAGE_NAME"
+ main() {
+   docker build --tag "$IMAGE_NAME" .
+   docker run --rm "$IMAGE_NAME"
+ }
+
+ main "$@"
```

---

<a id="use-defaults-in-functions"></a>

### `use-defaults-in-functions`

Use default or required-argument expansions when binding function positional parameters.

#### options

None.

<a id="use-defaults-in-functions-diff"></a>

#### do / don't

```diff
  deploy() {
-   local target="$1"
+   local target="${1:-staging}"
    upload "$target"
  }
```

---

<!-- comment rule behavior from internal/bash/rules.bash and internal/bash/lint.bash -->

<a id="no-unmatched-comments"></a>

### `no-unmatched-comments`

Reject comments that don't match a configured regular-expression matcher, prefix identifier, or suffix identifier.

Shebangs, ShellCheck directives, and `noqa` directives are ignored. No matcher or identifier is configured by default, so selecting this rule directly rejects ordinary comments.

This repo selects all three comment rules in `.shellcheck-legibility.yml` and allows only the `!NOTE` prefix. `AGENTS.md` reserves that marker for code comments explicitly requested by a human.

#### options

- `comment-matchers`: case-insensitive Bash regular expressions matched anywhere in the comment body. Default: `[]`.
- `comment-prefix-identifiers`: case-insensitive literal identifiers matched at the start of the trimmed comment body. Default: `[]`.
- `comment-suffix-identifiers`: case-insensitive literal identifiers matched at the end of the trimmed comment body. Default: `[]`.

<a id="no-unmatched-comments-diff"></a>

#### do / don't

```diff
- # explain this branch
+ require_target
```

With `KEEP` as an allowed prefix identifier:

```diff
- # preserve the legacy response order
+ # KEEP: preserve the legacy response order
```

---

<a id="no-automated-comment-attribution"></a>

### `no-automated-comment-attribution`

Reject explicit automated authorship and generation signatures in comments. Ordinary references to the configured technologies are unchanged.

#### options

- `automated-comment-identifiers`: case-insensitive names treated as automated sources. Default: `ai`, `chatgpt`, `claude`, `codex`, `copilot`, `gemini`, `gpt`, `llm`, and `openai`.

<a id="no-automated-comment-attribution-diff"></a>

#### do / don't

```diff
- # <configured identifier>-generated.
+ retry_in_provider_order
```

Structured `@author` tags and phrases like `generated by <identifier>` or `<identifier>-generated` are rejected. Unmarked prose is not classified.

---

<a id="no-stacked-comments"></a>

### `no-stacked-comments`

Report the second and subsequent comments on consecutive lines. A blank or non-comment line breaks the stack. Shebangs, ShellCheck directives, and `noqa` directives are ignored.

This rule has no options.

<a id="no-stacked-comments-diff"></a>

#### do / don't

```diff
- # Retry every failed request.
  # Retry requests that fail during regional failover.
```

## Recipes

The comment rules are explicit policy opt-ins and are excluded from broad selectors. Put the policy in a supported RC, YAML, or TOML file and select the rules directly by code or name.

```yaml
select: [LEG, LEG041, LEG042, LEG043]
comment-matchers:
  - '(^|[^[:alnum:]_])(ENG|OPS)-[0-9]+([^[:alnum:]_]|$)'
comment-prefix-identifiers: [KEEP]
comment-suffix-identifiers: ["@keep"]
```

This rejects unmarked comments, explicit automated attribution, and adjacent comments. Configure identifiers only for established repo conventions – don't add a marker just to make a new comment pass.

Use `--exit-zero` for advisory feedback. Enforcement should use the same committed config without `--exit-zero`.

## Use

```sh
bin/shellcheck-legibility check scripts tests
bin/shellcheck-legibility check . --select LEG001,LEG002 --ignore LEG038
bin/shellcheck-legibility check . --output-format json
```

Run `make build` first when working from source. Installed releases use `shellcheck-legibility` directly.

Directory scans skip symlinks. An explicitly named symlink to a regular shell file is checked under that path; symlinked directories aren't traversed. Overlapping targets are checked once per absolute path, preserving the first path spelling in diagnostics. Different symlink paths stay distinct because filename rules depend on the path.

Exclusions apply to directory scans; explicitly named files bypass them. Exclusion entries match exact discovered paths or directory components – not globs or arbitrary filename suffixes. For example, `vendor` skips a directory with that name anywhere in the scan. To exclude one file from `check .`, use its discovered path, like `./scripts/generated.sh`.

## Configuration

Config loads from the first matching file found while searching upward:

- `.shellcheck-legibilityrc` with `key=value` or `key: value` assignments.
- `.shellcheck-legibility.yml` or `.shellcheck-legibility.yaml` with YAML mappings and inline or block lists.
- `shellcheck-legibility.toml` or `.shellcheck-legibility.toml` with TOML assignments.

```toml
max-expression-operators = 4
max-if-operators = 0
max-control-flow-depth = 3
max-function-lines = 20
min-case-chain-length = 3
min-object-lookup-chain-length = 3
min-dirname-match-depth = 3
comment-matchers = []
comment-prefix-identifiers = []
comment-suffix-identifiers = []
automated-comment-identifiers = ["ai", "chatgpt", "claude", "codex", "copilot", "gemini", "gpt", "llm", "openai"]
```

Selectors use the same model as the other legibility tools: `select`, `ignore`, rule codes, rule names, and `LEG`.
Comment rules are policy opt-ins and are excluded from the broad `LEG` and `all` selectors.

## Tests

Build the native engine with Go 1.26 or later:

```sh
make build
```

This creates the ignored `bin/shellcheck-legibility` binary. Rebuild after changing Go or embedded Bash source. Set `SHELLCHECK_LEGIBILITY_ENGINE=bash` to compare against the Bash compatibility implementation.

Go unit tests live beside the code and have their own cases. Integration tests live in `tests/integration/`; packaged installation tests live in `tests/e2e/`. See [Contributing](.github/CONTRIBUTING.md) for the layout and rule development workflow.

Install the repo's pre-commit hook once per clone:

```sh
make install-hooks
```

The setup script installs `.git/hooks/pre-commit`, preserves unmanaged hooks, and skips CI. The hook runs ShellCheck, shfmt, unit and integration tests, system Bash compatibility, and configured legibility checks for staged files. `make check` runs the full-repo legibility scan and packaged-binary Docker tests too.

```sh
make unit
make integration
make e2e
make pre-commit
make check
```

## Publishing

```sh
gh workflow run release.yml --ref main -f tag=v0.2.6
```
