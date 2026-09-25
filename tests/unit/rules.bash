#!/usr/bin/env bash
# shellcheck disable=SC2034

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGED_HOOK_TEST_DIR=""

# shellcheck disable=SC1091
# shellcheck source=../../lib/defaults.bash
source "$ROOT_DIR/lib/defaults.bash"
# shellcheck disable=SC1091
# shellcheck source=../../lib/util.bash
source "$ROOT_DIR/lib/util.bash"
# shellcheck disable=SC1091
# shellcheck source=../../lib/config.bash
source "$ROOT_DIR/lib/config.bash"
# shellcheck disable=SC1091
# shellcheck source=../../lib/rules.bash
source "$ROOT_DIR/lib/rules.bash"
# shellcheck disable=SC1091
# shellcheck source=../../lib/files.bash
source "$ROOT_DIR/lib/files.bash"
# shellcheck disable=SC1091
# shellcheck source=../../lib/lint.bash
source "$ROOT_DIR/lib/lint.bash"

main() {
  test_version_metadata
  test_core_rules
  test_function_rules
  test_comment_rules
  test_config_formats
  test_false_positive_regressions
  test_shell_syntax_regressions
  test_staged_hook_uses_index_content
  printf '%s\n' "ok"
}

test_staged_hook_uses_index_content() {
  local file output
  STAGED_HOOK_TEST_DIR="$(mktemp -d "$ROOT_DIR/.staged-hook-test.XXXXXX")"
  trap cleanup_staged_hook_test EXIT
  setup_staged_hook_fixture "$STAGED_HOOK_TEST_DIR"
  file=$'nested/odd\npath[1].sh'
  prepare_staged_hook_file "$STAGED_HOOK_TEST_DIR" "$file"
  output="$(env -i PATH="$PATH" "$STAGED_HOOK_TEST_DIR/scripts/setup/check-staged.sh")"
  assert_equal "staged contents" "$output"
  cleanup_staged_hook_test
  trap - EXIT
}

setup_staged_hook_fixture() {
  local dir="${1:-}"
  mkdir -p "$dir/scripts/setup" "$dir/bin"
  cp "$ROOT_DIR/scripts/setup/check-staged.sh" "$dir/scripts/setup/check-staged.sh"
  write_staged_hook_linter "$dir/bin/shellcheck-legibility"
  chmod +x "$dir/bin/shellcheck-legibility"
  isolated_test_git -C "$dir" init -q
  isolated_test_git -C "$dir" config user.name "Unit Test"
  isolated_test_git -C "$dir" config user.email "unit-test@example.invalid"
}

isolated_test_git() {
  env -i PATH="$PATH" git "$@"
}

write_staged_hook_linter() {
  local path="${1:-}"
  cat > "$path" << 'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "check" ]]
shift
for file in "$@"; do
  cat "$file"
done
STUB
}

prepare_staged_hook_file() {
  local dir="${1:-}" file="${2:-}"
  mkdir -p "$(dirname "$dir/$file")"
  printf '%s\n' "staged contents" > "$dir/$file"
  isolated_test_git -C "$dir" add -- "$file"
  printf '%s\n' "unstaged contents" > "$dir/$file"
}

cleanup_staged_hook_test() {
  [[ -z "$STAGED_HOOK_TEST_DIR" ]] || rm -rf -- "$STAGED_HOOK_TEST_DIR"
  STAGED_HOOK_TEST_DIR=""
}

test_config_formats() {
  test_config_fixture "rc" ".shellcheck-legibilityrc" "17"
  test_config_fixture "yaml" ".shellcheck-legibility.yml" "18"
  test_config_fixture "toml" "shellcheck-legibility.toml" "19"
  test_yaml_config_list_values
  test_inline_yaml_list_values
}

test_config_fixture() {
  local format="${1:-}"
  local filename="${2:-}"
  local expected_max="${3:-}"
  local dir path resolved
  reset_test_state
  dir="$ROOT_DIR/tests/fixtures/config/$format"
  path="$dir/$filename"
  resolved="$(config_in_dir "$dir")"
  assert_equal "$path" "$resolved"
  read_config_file "$path"
  assert_equal "$expected_max" "$MAX_FUNCTION_LINES"
  assert_equal "LEG LEG041" "${SELECT[*]}"
}

test_yaml_config_list_values() {
  local path
  reset_test_state
  path="$ROOT_DIR/tests/fixtures/config/yaml/.shellcheck-legibility.yml"
  read_config_file "$path"
  assert_equal "4" "${#COMMENT_MATCHERS[@]}"
  assert_equal '^ticket,[0-9]+$' "${COMMENT_MATCHERS[0]}"
  assert_equal '^issue#[0-9]+$' "${COMMENT_MATCHERS[1]}"
  assert_equal '^file\.sh$' "${COMMENT_MATCHERS[2]}"
  assert_equal '^unicode.value$' "${COMMENT_MATCHERS[3]}"
}

test_inline_yaml_list_values() {
  local path
  reset_test_state
  path="$ROOT_DIR/tests/fixtures/config/yaml/inline-lists.yml"
  read_config_file "$path"
  assert_equal "6" "${#COMMENT_MATCHERS[@]}"
  assert_equal '^foo,(bar|baz)$' "${COMMENT_MATCHERS[0]}"
  assert_equal '^issue#[0-9]+$' "${COMMENT_MATCHERS[1]}"
  assert_equal '^file\.sh$' "${COMMENT_MATCHERS[2]}"
  assert_equal '^unicode.value$' "${COMMENT_MATCHERS[3]}"
  assert_equal $'^back\bspace$' "${COMMENT_MATCHERS[4]}"
  assert_equal $'^form\ffeed$' "${COMMENT_MATCHERS[5]}"
}

test_version_metadata() {
  local reported
  reported="$("$ROOT_DIR/bin/shellcheck-legibility" --version)"
  assert_equal "0.2.1" "$reported"
}

test_core_rules() {
  test_hoist_if_operators
  test_max_expression_operators
  test_bool_literal_args
  test_direct_shell_bin_smoke
  test_max_function_lines
  test_prefer_functions
  test_prefer_functions_allows_dispatch
  test_selected_line_rule_skips_other_analysis
  test_file_rule_skips_source_scan
}

test_selected_line_rule_skips_other_analysis() {
  reset_test_state
  SELECT=("LEG001")
  MAX_EXPRESSION_OPERATORS=0
  scan_fixture 'run() {' 'first && second' '}'
  assert_has_code "LEG001"
  assert_equal "0" "$CONTROL_FLOW_DEPTH"
  assert_equal "0" "$IN_FUNCTION"
}

test_file_rule_skips_source_scan() {
  reset_test_state
  SELECT=("LEG025")
  lint_file "$ROOT_DIR/tests/unit/rules.bash"
  assert_equal "0" "$SCAN_LINE_NUMBER"
}

test_function_rules() {
  test_use_defaults_in_functions
  test_use_defaults_in_functions_allows_defaults
  test_use_defaults_in_functions_reports_separate_assignment
  test_use_defaults_in_functions_reports_transformed_arg
  test_use_defaults_in_functions_reports_single_line_function
  test_use_defaults_in_functions_reports_opening_line_binding
  test_use_defaults_in_functions_reports_declare_binding
  test_use_defaults_in_functions_reports_typeset_binding
  test_use_defaults_in_functions_allows_global_declare
  test_use_defaults_in_functions_allows_assign_default
  test_use_defaults_in_functions_reports_command_list_assignment
  test_split_function_declaration_reports_arg_binding
  test_inline_function_does_not_leak_function_state
  test_function_state_closes_with_trailing_semicolon
}

test_comment_rules() {
  test_comment_matching_rules
  test_comment_stacking_rules
  test_comment_attribution_rules
}

test_comment_matching_rules() {
  test_no_unmatched_comments
  test_no_unmatched_comments_allows_prefix_identifier
  test_no_unmatched_comments_allows_suffix_identifier
  test_no_unmatched_comments_allows_exact_suffix_identifier
  test_no_unmatched_comments_allows_matcher
  test_no_unmatched_comments_rejects_partial_identifiers
  test_no_unmatched_comments_ignores_directives
  test_no_unmatched_comments_skips_quoted_hashes
  test_comment_rules_are_opt_in
  test_comment_rule_names_select_explicitly
  test_comment_rules_cache_disabled_state
}

test_comment_stacking_rules() {
  test_no_stacked_comments
  test_no_stacked_comments_rule_function
  test_no_stacked_comments_reports_each_addition
  test_no_stacked_comments_allows_separation
  test_no_stacked_comments_ignores_directives
  test_no_stacked_comments_ignores_non_comments
  test_no_stacked_comments_selects_by_name
}

test_comment_attribution_rules() {
  test_comment_attribution_matching
  test_comment_syntax_scanner
}

test_comment_attribution_matching() {
  test_no_automated_comment_attribution
  test_no_automated_comment_attribution_detects_author
  test_no_automated_comment_attribution_allows_references
  test_no_automated_comment_attribution_allows_mid_phrase_identifiers
  test_no_automated_comment_attribution_detects_article_signature
  test_no_automated_comment_attribution_detects_trailing_prose
  test_no_automated_comment_attribution_detects_conjunction
  test_no_automated_comment_attribution_supports_custom_identifiers
  test_no_automated_comment_attribution_allows_empty_identifiers
  test_no_automated_comment_attribution_ignores_directives
  test_no_automated_comment_attribution_skips_quoted_hashes
}

test_comment_syntax_scanner() {
  test_scan_line_runs_comment_policy
  test_scan_line_skips_heredoc_payload
  test_scan_line_skips_tab_stripped_heredoc_payload
  test_scan_line_closes_escaped_heredoc
  test_scan_line_closes_quoted_heredoc_with_spaces
  test_scan_line_defers_heredoc_across_continuation
  test_scan_line_activates_heredoc_after_blank_continuation
  test_scan_line_detects_quoted_command_substitution_heredoc
  test_scan_line_detects_comment_in_case_arm_substitution
  test_scan_line_skips_ansi_c_quoted_hash
  test_scan_line_detects_comment_in_backtick_substitution
  test_scan_line_preserves_multiline_quote_state
}

reset_test_state() {
  reset_test_config
  init_defaults
  reset_test_diagnostics
  CURRENT_LINE_TEXT=""
  invalidate_comment_rule_state
  reset_scan_state "example.sh"
}

reset_test_config() {
  SELECT=()
  IGNORE=()
  EXCLUDE=()
  EXECUTABLE_ENTRY_PATTERNS=()
  DIRECT_SHELL_ENTRY_PATTERNS=()
  EXECUTABLE_RUNTIMES=()
  COMMENT_MATCHERS=()
  COMMENT_PREFIX_IDENTIFIERS=()
  COMMENT_SUFFIX_IDENTIFIERS=()
  AUTOMATED_COMMENT_IDENTIFIERS=()
}

reset_test_diagnostics() {
  DIAG_CODES=()
  DIAG_PATHS=()
  DIAG_LINES=()
  DIAG_COLUMNS=()
  DIAG_RULES=()
  DIAG_MESSAGES=()
}

test_hoist_if_operators() {
  reset_test_state
  check_hoist_if_operators "example.sh" "4" 'if [[ -n "$user" && -n "$email" ]]; then'
  assert_has_code "LEG002"
}

test_max_expression_operators() {
  reset_test_state
  MAX_EXPRESSION_OPERATORS="1"
  check_max_expression_operators "example.sh" "7" 'build && test && package'
  assert_has_code "LEG001"
}

test_bool_literal_args() {
  reset_test_state
  check_no_bool_literal_args "example.sh" "9" 'create_user "$name" true false' # noqa: LEG035
  assert_has_code "LEG035"
}

test_direct_shell_bin_smoke() {
  reset_test_state
  check_no_direct_shell_bin_smoke "smoke.sh" "3" 'bash scripts/example.sh --help'
  assert_has_code "LEG017"
}

test_max_function_lines() {
  reset_test_state
  MAX_FUNCTION_LINES="3"
  check_max_function_lines "example.sh" "1" "5"
  assert_has_code "LEG038"
}

test_prefer_functions() {
  reset_test_state
  check_prefer_functions "example.sh" "5" "docker build ."
  assert_has_code "LEG039"
}

test_prefer_functions_allows_dispatch() {
  reset_test_state
  FUNCTION_NAMES+=("main")
  check_prefer_functions "example.sh" "12" 'main "$@"'
  assert_no_diagnostics
}

test_use_defaults_in_functions() {
  reset_test_state
  IN_FUNCTION="1"
  check_use_defaults_in_functions "example.sh" "6" 'local target="$1"'
  assert_has_code "LEG040"
}

test_use_defaults_in_functions_allows_defaults() {
  reset_test_state
  IN_FUNCTION="1"
  check_use_defaults_in_functions "example.sh" "6" 'local target="${1:-dev}"'
  assert_no_diagnostics
}

test_use_defaults_in_functions_reports_separate_assignment() {
  reset_test_state
  IN_FUNCTION="1"
  check_use_defaults_in_functions "example.sh" "7" 'target="$1"'
  assert_has_code "LEG040"
}

test_use_defaults_in_functions_reports_transformed_arg() {
  reset_test_state
  IN_FUNCTION="1"
  check_use_defaults_in_functions "example.sh" "8" 'local base="${1%.ext}"'
  assert_has_code "LEG040"
}

test_use_defaults_in_functions_reports_single_line_function() {
  reset_test_state
  check_use_defaults_in_functions "example.sh" "3" 'deploy() { local target="$1"; upload "$target"; }'
  assert_has_code "LEG040"
}

test_use_defaults_in_functions_reports_opening_line_binding() {
  reset_test_state
  check_use_defaults_in_functions "example.sh" "3" 'deploy() { local target="$1"'
  assert_has_code "LEG040"
}

test_use_defaults_in_functions_reports_declare_binding() {
  reset_test_state
  IN_FUNCTION="1"
  check_use_defaults_in_functions "example.sh" "7" 'declare target="$1"'
  assert_has_code "LEG040"
}

test_use_defaults_in_functions_reports_typeset_binding() {
  reset_test_state
  IN_FUNCTION="1"
  check_use_defaults_in_functions "example.sh" "7" 'typeset target="$1"'
  assert_has_code "LEG040"
}

test_use_defaults_in_functions_allows_global_declare() {
  reset_test_state
  IN_FUNCTION="1"
  check_use_defaults_in_functions "example.sh" "7" 'declare -g target="$1"'
  assert_no_diagnostics
}

test_use_defaults_in_functions_allows_assign_default() {
  reset_test_state
  IN_FUNCTION="1"
  check_use_defaults_in_functions "example.sh" "7" 'local target="${1:=staging}"'
  check_use_defaults_in_functions "example.sh" "8" 'local mode="${1=dev}"'
  assert_no_diagnostics
}

test_use_defaults_in_functions_reports_command_list_assignment() {
  reset_test_state
  IN_FUNCTION="1"
  check_use_defaults_in_functions "example.sh" "7" 'prepare && target="$1"' # noqa: LEG040
  assert_has_code "LEG040"
}

test_split_function_declaration_reports_arg_binding() {
  reset_test_state
  scan_line "example.sh" "1" "deploy()"
  assert_no_diagnostics
  scan_line "example.sh" "2" "{"
  assert_no_diagnostics
  scan_line "example.sh" "3" 'local target="$1"'
  assert_has_code "LEG040"
}

test_inline_function_does_not_leak_function_state() {
  reset_test_state
  update_function_state "example.sh" "3" 'deploy() { local target="${1:-staging}"; }'
  [[ "$IN_FUNCTION" == "0" ]] || fail "expected inline function to stay closed"
}

test_function_state_closes_with_trailing_semicolon() {
  reset_test_state
  SELECT=("LEG039")
  scan_fixture 'broken() {' ':' '};' 'docker build .'
  assert_equal "0" "$IN_FUNCTION"
  assert_has_code "LEG039"
}

test_no_unmatched_comments() {
  reset_test_state
  SELECT=("LEG041")
  check_no_unmatched_comments "example.sh" "4" "# explain this branch"
  assert_has_code "LEG041"
}

test_no_unmatched_comments_allows_prefix_identifier() {
  reset_test_state
  SELECT=("LEG041")
  COMMENT_PREFIX_IDENTIFIERS+=("KEEP")
  check_no_unmatched_comments "example.sh" "4" "# KEEP: legacy API order"
  assert_no_diagnostics
}

test_no_unmatched_comments_allows_suffix_identifier() {
  reset_test_state
  SELECT=("LEG041")
  COMMENT_SUFFIX_IDENTIFIERS+=("@keep")
  check_no_unmatched_comments "example.sh" "4" 'deploy "$target" # preserve order @keep'
  assert_no_diagnostics
}

test_no_unmatched_comments_allows_exact_suffix_identifier() {
  reset_test_state
  SELECT=("LEG041")
  COMMENT_SUFFIX_IDENTIFIERS+=("@keep")
  check_no_unmatched_comments "example.sh" "4" "# @keep"
  assert_no_diagnostics
}

test_no_unmatched_comments_allows_matcher() {
  reset_test_state
  SELECT=("LEG041")
  COMMENT_MATCHERS+=("ENG-[0-9]+")
  check_no_unmatched_comments "example.sh" "4" "# ENG-482 tracks this branch"
  assert_no_diagnostics
}

test_no_unmatched_comments_rejects_partial_identifiers() {
  reset_test_state
  SELECT=("LEG041")
  COMMENT_PREFIX_IDENTIFIERS+=("KEEP")
  COMMENT_SUFFIX_IDENTIFIERS+=("@keep")
  check_no_unmatched_comments "example.sh" "4" "# KEEPING generated not@keep"
  assert_has_code "LEG041"
}

test_no_unmatched_comments_ignores_directives() {
  reset_test_state
  SELECT=("LEG041")
  check_no_unmatched_comments "example.sh" "1" "#!/usr/bin/env bash"
  check_no_unmatched_comments "example.sh" "2" "# shellcheck disable=SC1091"
  check_no_unmatched_comments "example.sh" "3" "# noqa: LEG041"
  assert_no_diagnostics
}

test_no_unmatched_comments_skips_quoted_hashes() {
  reset_test_state
  SELECT=("LEG041")
  check_no_unmatched_comments "example.sh" "7" "printf '%s\n' '#!/usr/bin/env bash'"
  assert_no_diagnostics
}

test_no_stacked_comments() {
  reset_test_state
  SELECT=("LEG043")
  scan_line "example.sh" "1" "# First comment."
  scan_line "example.sh" "2" "# Second comment."
  assert_equal "1" "${#DIAG_CODES[@]}"
  assert_has_code "LEG043"
}

test_no_stacked_comments_rule_function() {
  reset_test_state
  SELECT=("LEG043")
  check_no_stacked_comments "example.sh" "1" "# First comment."
  check_no_stacked_comments "example.sh" "2" "# Second comment."
  assert_has_code "LEG043"
}

test_no_stacked_comments_reports_each_addition() {
  reset_test_state
  SELECT=("LEG043")
  scan_line "example.sh" "1" "# First comment."
  scan_line "example.sh" "2" "# Second comment."
  scan_line "example.sh" "3" "# Third comment."
  assert_equal "2" "${#DIAG_CODES[@]}"
}

test_no_stacked_comments_allows_separation() {
  reset_test_state
  SELECT=("LEG043")
  scan_line "example.sh" "1" "# First comment."
  scan_line "example.sh" "3" "# Second comment."
  scan_line "example.sh" "4" "printf '%s\n' value"
  scan_line "example.sh" "5" "# Third comment."
  assert_no_diagnostics
}

test_no_stacked_comments_ignores_directives() {
  reset_test_state
  SELECT=("LEG043")
  scan_line "example.sh" "1" "#!/usr/bin/env bash"
  scan_line "example.sh" "2" "# shellcheck disable=SC1091"
  scan_line "example.sh" "3" "# noqa: LEG043"
  scan_line "example.sh" "4" "# First comment."
  assert_no_diagnostics
}

test_no_stacked_comments_ignores_non_comments() {
  reset_test_state
  SELECT=("LEG043")
  scan_line "example.sh" "1" "printf '%s\n' '# Quoted.'"
  scan_line "example.sh" "2" "# First comment."
  scan_line "example.sh" "3" "cat <<'EOF'"
  scan_line "example.sh" "4" "# Heredoc payload."
  scan_line "example.sh" "5" "EOF"
  scan_line "example.sh" "6" "# Second comment."
  assert_no_diagnostics
}

test_no_stacked_comments_selects_by_name() {
  reset_test_state
  SELECT=("no-stacked-comments")
  scan_line "example.sh" "1" "# First comment."
  scan_line "example.sh" "2" "# Second comment."
  assert_has_code "LEG043"
}

test_comment_rules_are_opt_in() {
  local identifier signature selector
  identifier="code""x"
  signature="# Generated by $identifier."
  for selector in LEG all; do
    reset_test_state
    SELECT=("$selector")
    check_no_unmatched_comments "example.sh" "4" "# explain this branch"
    check_no_automated_comment_attribution "example.sh" "5" "$signature"
    scan_line "example.sh" "6" "# First comment."
    scan_line "example.sh" "7" "# Second comment."
    assert_no_diagnostics
  done
}

test_comment_rule_names_select_explicitly() {
  reset_test_state
  SELECT=("no-unmatched-comments")
  check_no_unmatched_comments "example.sh" "4" "# explain this branch"
  assert_has_code "LEG041"
}

test_comment_rules_cache_disabled_state() {
  reset_test_state
  prepare_comment_rule_state
  assert_equal "0" "$COMMENT_RULES_ENABLED"
  assert_equal "0" "$NO_UNMATCHED_COMMENTS_ENABLED"
  assert_equal "0" "$NO_AUTOMATED_COMMENT_ATTRIBUTION_ENABLED"
  assert_equal "0" "$NO_STACKED_COMMENTS_ENABLED"
}

test_no_automated_comment_attribution() {
  reset_test_state
  local identifier signature
  identifier="code""x"
  signature="# Generated by $identifier."
  SELECT=("LEG042")
  check_no_automated_comment_attribution "example.sh" "4" "$signature"
  assert_has_code "LEG042"
}

test_no_automated_comment_attribution_detects_author() {
  reset_test_state
  local identifier signature
  identifier="open""ai"
  signature="# @AUTHOR: $identifier"
  SELECT=("LEG042")
  check_no_automated_comment_attribution "example.sh" "4" "$signature"
  assert_has_code "LEG042"
}

test_no_automated_comment_attribution_allows_references() {
  reset_test_state
  SELECT=("LEG042")
  check_no_automated_comment_attribution "example.sh" "4" "# Send the request to OpenAI."
  check_no_automated_comment_attribution "example.sh" "5" "# Parse the AI response."
  assert_no_diagnostics
}

test_no_automated_comment_attribution_allows_mid_phrase_identifiers() {
  reset_test_state
  local identifier author_reference pipeline_reference
  identifier="a""i"
  author_reference="# Written by an $identifier engineer."
  pipeline_reference="# Generated by ${identifier}-assisted tooling."
  SELECT=("LEG042")
  check_no_automated_comment_attribution "example.sh" "4" "$author_reference"
  check_no_automated_comment_attribution "example.sh" "5" "$pipeline_reference"
  assert_no_diagnostics
}

test_no_automated_comment_attribution_detects_article_signature() {
  reset_test_state
  local identifier signature
  identifier="a""i"
  signature="# Generated by an $identifier."
  SELECT=("LEG042")
  check_no_automated_comment_attribution "example.sh" "4" "$signature"
  assert_has_code "LEG042"
}

test_no_automated_comment_attribution_detects_trailing_prose() {
  reset_test_state
  local identifier signature
  identifier="code""x"
  signature="# Generated by $identifier; do not edit."
  SELECT=("LEG042")
  check_no_automated_comment_attribution "example.sh" "4" "$signature"
  assert_has_code "LEG042"
}

test_no_automated_comment_attribution_detects_conjunction() {
  reset_test_state
  local identifier signature
  identifier="code""x"
  signature="# Generated by $identifier and reviewed by Alice."
  SELECT=("LEG042")
  check_no_automated_comment_attribution "example.sh" "4" "$signature"
  assert_has_code "LEG042"
}

test_no_automated_comment_attribution_supports_custom_identifiers() {
  reset_test_state
  local identifier signature
  identifier="robot"
  signature="# ${identifier}-authored."
  SELECT=("LEG042")
  apply_comment_config_value "automated-comment-identifiers" "[\"$identifier\"]"
  check_no_automated_comment_attribution "example.sh" "4" "$signature"
  assert_has_code "LEG042"
}

test_no_automated_comment_attribution_allows_empty_identifiers() {
  reset_test_state
  local identifier signature
  identifier="code""x"
  signature="# Generated by $identifier."
  SELECT=("LEG042")
  apply_comment_config_value "automated-comment-identifiers" "[]"
  check_no_automated_comment_attribution "example.sh" "4" "$signature"
  assert_no_diagnostics
}

test_no_automated_comment_attribution_ignores_directives() {
  reset_test_state
  SELECT=("LEG042")
  check_no_automated_comment_attribution "example.sh" "1" "#!/usr/bin/env bash"
  check_no_automated_comment_attribution "example.sh" "2" "# shellcheck disable=SC1091"
  check_no_automated_comment_attribution "example.sh" "3" "# noqa: LEG042"
  assert_no_diagnostics
}

test_no_automated_comment_attribution_skips_quoted_hashes() {
  reset_test_state
  local identifier signature line
  identifier="code""x"
  signature="# Generated by $identifier."
  line="printf '%s\n' '$signature'"
  SELECT=("LEG042")
  check_no_automated_comment_attribution "example.sh" "7" "$line"
  assert_no_diagnostics
}

test_scan_line_runs_comment_policy() {
  reset_test_state
  local identifier signature
  identifier="code""x"
  signature="# Generated by $identifier."
  SELECT=("LEG041" "LEG042")
  scan_line "example.sh" "4" "$signature"
  assert_has_code "LEG041"
  assert_has_code "LEG042"
}

test_scan_line_skips_heredoc_payload() {
  reset_test_state
  local identifier signature
  identifier="code""x"
  signature="# Generated by $identifier."
  SELECT=("LEG041" "LEG042")
  scan_line "example.sh" "1" "cat <<'SCRIPT'"
  scan_line "example.sh" "2" ""
  scan_line "example.sh" "3" "$signature"
  scan_line "example.sh" "4" "SCRIPT"
  assert_no_diagnostics
  scan_line "example.sh" "5" "$signature"
  assert_has_code "LEG041"
  assert_has_code "LEG042"
}

test_scan_line_skips_tab_stripped_heredoc_payload() {
  reset_test_state
  local identifier signature
  identifier="code""x"
  signature="# Generated by $identifier."
  SELECT=("LEG041" "LEG042")
  scan_line "example.sh" "1" "cat <<-'SCRIPT'"
  scan_line "example.sh" "2" "$signature"
  scan_line "example.sh" "3" $'\tSCRIPT'
  assert_no_diagnostics
}

test_scan_line_closes_escaped_heredoc() {
  reset_test_state
  local identifier signature
  identifier="code""x"
  signature="# Generated by $identifier."
  SELECT=("LEG042")
  scan_line "example.sh" "1" "cat <<\\EOF"
  scan_line "example.sh" "2" "$signature"
  scan_line "example.sh" "3" "EOF"
  assert_no_diagnostics
  scan_line "example.sh" "4" "$signature"
  assert_has_code "LEG042"
}

test_scan_line_closes_quoted_heredoc_with_spaces() {
  reset_test_state
  local identifier signature
  identifier="code""x"
  signature="# Generated by $identifier."
  SELECT=("LEG042")
  scan_line "example.sh" "1" "cat <<'END MARK'"
  scan_line "example.sh" "2" "$signature"
  scan_line "example.sh" "3" "END MARK"
  assert_no_diagnostics
  scan_line "example.sh" "4" "$signature"
  assert_has_code "LEG042"
}

test_scan_line_defers_heredoc_across_continuation() {
  reset_test_state
  local identifier signature
  identifier="code""x"
  signature="# Generated by $identifier."
  SELECT=("LEG042")
  scan_line "example.sh" "1" 'cat <<EOF \'
  scan_line "example.sh" "2" "$signature"
  assert_equal "1" "${#DIAG_CODES[@]}"
  scan_line "example.sh" "3" "$signature"
  scan_line "example.sh" "4" "EOF"
  assert_equal "1" "${#DIAG_CODES[@]}"
  scan_line "example.sh" "5" "$signature"
  assert_equal "2" "${#DIAG_CODES[@]}"
}

test_scan_line_activates_heredoc_after_blank_continuation() {
  reset_test_state
  local identifier signature
  identifier="code""x"
  signature="# Generated by $identifier."
  SELECT=("LEG042")
  scan_line "example.sh" "1" 'cat <<EOF \'
  scan_line "example.sh" "2" ""
  assert_equal "1" "${#HEREDOC_DELIMITERS[@]}"
  scan_line "example.sh" "3" "$signature"
  assert_no_diagnostics
  scan_line "example.sh" "4" "EOF"
  scan_line "example.sh" "5" "$signature"
  assert_has_code "LEG042"
}

test_scan_line_detects_quoted_command_substitution_heredoc() {
  reset_test_state
  local identifier signature
  identifier="code""x"
  signature="# Generated by $identifier."
  SELECT=("LEG042")
  scan_line "example.sh" "1" "value=\"\$(cat <<'EOF'"
  scan_line "example.sh" "2" "$signature"
  scan_line "example.sh" "3" "EOF"
  scan_line "example.sh" "4" ')"'
  assert_no_diagnostics
}

test_scan_line_detects_comment_in_case_arm_substitution() {
  reset_test_state
  local identifier signature
  identifier="code""x"
  signature="# Generated by $identifier."
  SELECT=("LEG042")
  scan_line "example.sh" "1" 'value="$('
  scan_line "example.sh" "2" '  case "$target" in'
  scan_line "example.sh" "3" "    x) $signature"
  assert_has_code "LEG042"
}

test_scan_line_skips_ansi_c_quoted_hash() {
  reset_test_state
  local identifier signature line
  identifier="code""x"
  signature="# Generated by $identifier."
  line="value=\$'can\\'t $signature'"
  SELECT=("LEG041" "LEG042")
  scan_line "example.sh" "1" "$line"
  assert_no_diagnostics
}

test_scan_line_detects_comment_in_backtick_substitution() {
  reset_test_state
  local identifier signature
  identifier="code""x"
  signature="# Generated by $identifier."
  SELECT=("LEG042")
  scan_line "example.sh" "1" 'value="`printf ok'
  scan_line "example.sh" "2" "$signature"
  scan_line "example.sh" "3" '`"'
  assert_has_code "LEG042"
}

test_scan_line_preserves_multiline_quote_state() {
  reset_test_state
  local identifier signature
  identifier="code""x"
  signature="# Generated by $identifier."
  SELECT=("LEG042")
  scan_line "example.sh" "1" 'value="first line'
  scan_line "example.sh" "2" "$signature"
  scan_line "example.sh" "3" 'last line"'
  assert_no_diagnostics
  scan_line "example.sh" "4" "$signature"
  assert_has_code "LEG042"
}

assert_has_code() {
  local expected="${1:-}"
  local code
  for code in "${DIAG_CODES[@]}"; do
    [[ "$code" == "$expected" ]] && return
  done
  printf 'expected %s, got %s\n' "$expected" "${DIAG_CODES[*]}" >&2
  exit 1
}

assert_no_diagnostics() {
  [[ "${#DIAG_CODES[@]}" -eq 0 ]] && return
  printf 'expected no diagnostics, got %s\n' "${DIAG_CODES[*]}" >&2
  exit 1
}

assert_equal() {
  local expected="${1:-}"
  local actual="${2:-}"
  [[ "$actual" == "$expected" ]] && return
  printf 'expected %s, got %s\n' "$expected" "$actual" >&2
  exit 1
}

fail() {
  printf '%s\n' "${1:-}" >&2
  exit 1
}

test_false_positive_regressions() {
  test_guard_clause_allowed
  test_exit_guard_allowed
  test_wrapped_function_reported
  test_nested_guard_keeps_outer_diagnostic
  test_optional_branch_allowed
  test_bool_commands_allowed
  test_bool_argument_still_reported
  test_script_filename_policy_preserved
  test_component_filename_still_reported
  test_literal_operators_allowed
  test_heredoc_is_not_shell_syntax
  test_group_redirection_does_not_close_function
  test_case_parser_function_closes_before_next_function
  test_function_structural_state_is_restored
  test_real_function_lines_still_reported
}

scan_fixture() {
  local line number=0
  for line in "$@"; do
    number=$((number + 1))
    scan_line "example.sh" "$number" "$line"
  done
}

test_guard_clause_allowed() {
  reset_test_state
  SELECT=("LEG010")
  scan_fixture 'run() {' 'if ready; then' 'return 0' 'fi' 'work' '}'
  assert_no_diagnostics
}

test_wrapped_function_reported() {
  reset_test_state
  SELECT=("LEG010")
  scan_fixture 'run() {' 'if ready; then' 'build' 'upload' 'fi' '}'
  assert_has_code "LEG010"
  assert_equal "2" "${DIAG_LINES[0]}"
}

test_optional_branch_allowed() {
  reset_test_state
  SELECT=("LEG010")
  scan_fixture 'run() {' 'if verbose; then' 'log' 'fi' 'work' '}'
  assert_no_diagnostics
}

test_bool_commands_allowed() {
  reset_test_state
  SELECT=("LEG035")
  scan_fixture 'run || true' 'false || recover' 'run && false' 'command true'
  scan_fixture 'output="$(run || true)"' "printf '%s\\n' 'some true text'"
  assert_no_diagnostics
}

test_bool_argument_still_reported() {
  reset_test_state
  SELECT=("LEG035")
  scan_fixture 'run || create_user true'
  assert_has_code "LEG035"
}

test_script_filename_policy_preserved() {
  reset_test_state
  SELECT=("LEG025")
  check_require_filename_matches_dirname "tests/e2e/scripts/test-security.sh" "1"
  assert_has_code "LEG025"
}

test_component_filename_still_reported() {
  reset_test_state
  SELECT=("LEG025")
  check_require_filename_matches_dirname "src/deploy/release/unrelated.sh" "1"
  assert_has_code "LEG025"
}

test_literal_operators_allowed() {
  reset_test_state
  SELECT=("LEG001" "LEG002")
  MAX_EXPRESSION_OPERATORS=0
  MAX_CONDITION_OPERATORS=0
  scan_fixture "printf '%s\\n' 'one|two|three || four && five'"
  scan_fixture 'if grep -q "a || b && c" file; then' 'work' 'fi'
  assert_no_diagnostics
}

test_heredoc_is_not_shell_syntax() {
  reset_test_state
  SELECT=("LEG001" "LEG002" "LEG035")
  MAX_EXPRESSION_OPERATORS=0
  scan_fixture 'write() {' "cat <<'EOF'" 'true false || &&' '}' 'if data; then' 'EOF' '}'
  assert_no_diagnostics
  assert_equal "0" "$IN_FUNCTION"
}

test_real_function_lines_still_reported() {
  reset_test_state
  SELECT=("LEG038")
  MAX_FUNCTION_LINES=4
  scan_fixture 'run() {' 'first' 'second' 'third' '}'
  assert_has_code "LEG038"
}

test_shell_syntax_regressions() {
  test_optional_final_branch_allowed
  test_alternate_branches_allowed
  test_guard_directive_uses_opening_line
  test_case_patterns_are_not_pipelines
  test_shell_operators_still_reported
  test_multiline_literal_is_not_shell_code
  test_real_case_pipeline_still_reported
  test_bool_command_boundaries
  test_bool_after_quoted_arg_reported
  test_physical_function_lines_preserved
  test_heredoc_function_lines_preserved
  test_inline_conditionals_close
  test_inline_wrapped_function_reported
  test_inline_exit_guard_allowed
  test_inline_conditional_tail_allowed
  test_early_return_regressions
  test_exit_parser_empty_commands
  test_exit_parser_preserves_exit_commands
}

test_early_return_regressions() {
  test_inline_elif_else_does_not_report_early_return
  test_multiline_elif_else_does_not_report_early_return
  test_simple_else_after_exit_reports_early_return
}

test_exit_parser_empty_commands() {
  reset_test_state
  local line
  for line in 'work;' '(return)' '(work); work' 'work &' 'work || return'; do
    command_code_exits "$line"
    assert_equal "1" "$?"
  done
}

test_exit_parser_preserves_exit_commands() {
  reset_test_state
  local line
  for line in 'return;' '(work); return' 'work; exit 1' 'work && return || exit'; do
    command_code_exits "$line"
    assert_equal "0" "$?"
  done
}

test_inline_conditionals_close() {
  reset_test_state
  SELECT=("LEG003")
  MAX_CONTROL_FLOW_DEPTH=2
  scan_fixture 'if ready; then work; fi' 'if ready; then if enabled; then work; fi; fi'
  scan_fixture 'if ready; then' 'work' 'fi'
  assert_equal "0" "$IF_DEPTH"
  assert_equal "0" "$CONTROL_FLOW_DEPTH"
  assert_no_diagnostics
}

test_inline_wrapped_function_reported() {
  reset_test_state
  SELECT=("LEG010")
  scan_fixture 'run() {' 'if ready; then work; fi' '}'
  assert_has_code "LEG010"
  assert_equal "2" "${DIAG_LINES[0]}"
}

test_inline_exit_guard_allowed() {
  reset_test_state
  SELECT=("LEG010")
  scan_fixture 'run() {' 'if failed; then return 1; fi' '}'
  assert_no_diagnostics
}

test_inline_conditional_tail_allowed() {
  reset_test_state
  SELECT=("LEG010")
  scan_fixture 'run() {' 'if ready; then work; fi; finish' '}'
  assert_no_diagnostics
}

test_inline_elif_else_does_not_report_early_return() {
  reset_test_state
  SELECT=("LEG009")
  scan_fixture 'run() {' 'if x; then return; elif y; then work; else other; fi' '}'
  assert_no_diagnostics
}

test_multiline_elif_else_does_not_report_early_return() {
  reset_test_state
  SELECT=("LEG009")
  scan_fixture 'run() {' 'if x; then' 'return' 'elif y; then' 'work' 'else' 'other' 'fi' '}'
  assert_no_diagnostics
}

test_simple_else_after_exit_reports_early_return() {
  reset_test_state
  SELECT=("LEG009")
  scan_fixture 'run() {' 'if x; then return; else other; fi' '}'
  assert_has_code "LEG009"
}

test_optional_final_branch_allowed() {
  reset_test_state
  SELECT=("LEG010")
  scan_fixture 'run() {' 'work' 'if verbose; then' 'log' 'fi' '}'
  assert_no_diagnostics
}

test_alternate_branches_allowed() {
  reset_test_state
  SELECT=("LEG010")
  scan_fixture 'run() {' 'if ready; then' 'work' 'else' 'exit 1' 'fi' '}'
  assert_no_diagnostics
}

test_guard_directive_uses_opening_line() {
  reset_test_state
  SELECT=("LEG010")
  scan_fixture 'run() {' 'if ready; then # noqa: LEG010' 'work' 'fi' '}'
  assert_no_diagnostics
}

test_case_patterns_are_not_pipelines() {
  reset_test_state
  SELECT=("LEG001" "LEG035")
  MAX_EXPRESSION_OPERATORS=0
  scan_fixture 'case "$answer" in' 'true | false | yes | no)' 'work ;;' 'esac'
  assert_no_diagnostics
}

test_shell_operators_still_reported() {
  reset_test_state
  SELECT=("LEG001" "LEG002")
  MAX_EXPRESSION_OPERATORS=0
  MAX_CONDITION_OPERATORS=0
  scan_fixture 'value="$(first && second)"'
  assert_has_code "LEG001"
  scan_fixture 'if ! ready; then' 'work' 'fi'
  assert_has_code "LEG002"
}

test_multiline_literal_is_not_shell_code() {
  reset_test_state
  SELECT=("LEG001" "LEG002" "LEG035")
  scan_fixture 'run() {' "node -e '" 'if (ready && true) {' 'return false;' '}' "'" '}'
  assert_no_diagnostics
}

test_real_case_pipeline_still_reported() {
  reset_test_state
  SELECT=("LEG001")
  MAX_EXPRESSION_OPERATORS=0
  scan_fixture 'case "$answer" in' 'yes | no) first | second ;;' 'esac'
  assert_has_code "LEG001"
}

test_bool_command_boundaries() {
  reset_test_state
  SELECT=("LEG035")
  scan_fixture '{ true; }' 'if true; then' 'command -v true' 'fi' 'run > true'
  assert_no_diagnostics
}

test_bool_after_quoted_arg_reported() {
  reset_test_state
  SELECT=("LEG035")
  scan_fixture 'create_user "$name" false'
  assert_has_code "LEG035"
}

test_physical_function_lines_preserved() {
  reset_test_state
  SELECT=("LEG038")
  MAX_FUNCTION_LINES=3
  scan_fixture 'run() {' '# context' '' 'work' '# context' '}'
  assert_has_code "LEG038"
  assert_equal "Function has 6 lines (max 3). Extract focused helper functions." "${DIAG_MESSAGES[0]}"
}

test_exit_guard_allowed() {
  reset_test_state
  SELECT=("LEG010")
  scan_fixture 'run() {' 'if failed; then' 'exit 1' 'fi' '}'
  assert_no_diagnostics
}

test_nested_guard_keeps_outer_diagnostic() {
  reset_test_state
  SELECT=("LEG010")
  scan_fixture 'run() {' 'if ready; then' 'if failed; then' 'return 1' 'fi' 'work' 'fi' '}'
  assert_has_code "LEG010"
  assert_equal "2" "${DIAG_LINES[0]}"
}

test_heredoc_function_lines_preserved() {
  reset_test_state
  SELECT=("LEG038")
  MAX_FUNCTION_LINES=4
  scan_fixture 'write() {' "cat <<'EOF'" 'data' '}' 'more data' 'EOF' '}'
  assert_has_code "LEG038"
  assert_equal "Function has 7 lines (max 4). Extract focused helper functions." "${DIAG_MESSAGES[0]}"
}

test_group_redirection_does_not_close_function() {
  reset_test_state
  SELECT=("LEG039")
  scan_fixture 'write_bundle() {' '{' 'printf output' '} > "$bundle_path"' 'chmod +x "$bundle_path"' '}'
  assert_no_diagnostics
}

test_case_parser_function_closes_before_next_function() {
  reset_test_state
  SELECT=("LEG039")
  scan_case_keyword_fixture
  assert_equal "0" "${#SHELL_CASE_STATES[@]}"
  assert_equal "0" "$IN_FUNCTION"
  assert_equal "0" "$CONTROL_FLOW_DEPTH"
  assert_has_code "LEG039"
}

scan_case_keyword_fixture() {
  scan_fixture \
    'check_words() {' \
    'for word in "${words[@]}"; do' \
    'case "$word" in' \
    '"(") paren_depth=$((paren_depth + 1)); continue ;;' \
    'esac' \
    'case "$word" in' \
    '__SEQUENCE__|__AND__|__OR__) expecting_command="1"; continue ;;' \
    'esac' \
    'case "$word" in' \
    "if|then|elif|else|fi|while|until|for|select|do|done|case|'esac') return 0 ;;" \
    'esac' 'done' 'return 1' '}' 'docker build .'
}

test_function_structural_state_is_restored() {
  reset_test_state
  SELECT=("LEG039")
  scan_fixture 'broken() {' 'if ready; then' 'work' '}' 'docker build .'
  assert_equal "0" "$CONTROL_FLOW_DEPTH"
  assert_equal "0" "$IF_DEPTH"
  assert_has_code "LEG039"
}

main "$@"
