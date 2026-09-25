package lint

import "testing"

func TestAlternateBranchesAllowed(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG010"}
	source := `run() {
if ready; then
work
else
exit 1
fi
}
`
	assertScan(t, source, config, nil)
}

func TestBoolArgumentStillReported(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG035"}
	source := `run || create_user true
`
	want := []expectedDiagnostic{
		{"LEG035", 1, 1, "Avoid boolean literal arguments. Name the option before passing it."},
	}
	assertScan(t, source, config, want)
}

func TestBoolCommandBoundaries(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG035"}
	source := `{ true; }
if true; then
command -v true
fi
run > true
`
	assertScan(t, source, config, nil)
}

func TestBoolCommandsAllowed(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG035"}
	source := `output="$(run || true)"
printf '%s\n' 'some true text'
run && false
command true
`
	assertScan(t, source, config, nil)
}

func TestExitGuardAllowed(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG010"}
	source := `run() {
if failed; then
exit 1
fi
}
`
	assertScan(t, source, config, nil)
}

func TestFunctionStateClosesWithTrailingSemicolon(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG039"}
	source := `broken() {
:
};
docker build .
`
	want := []expectedDiagnostic{
		{"LEG039", 4, 1, "Move top-level script logic into named functions and keep only setup plus function dispatch at the top level."},
	}
	assertScan(t, source, config, want)
}

func TestGroupRedirectionDoesNotCloseFunction(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG039"}
	source := `write_bundle() {
{
printf output
} > "$bundle_path"
chmod +x "$bundle_path"
}
`
	assertScan(t, source, config, nil)
}

func TestGuardClauseAllowed(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG010"}
	source := `run() {
if ready; then
return 0
fi
work
}
`
	assertScan(t, source, config, nil)
}

func TestGuardDirectiveUsesOpeningLine(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG010"}
	source := `run() {
if ready; then # noqa: LEG010
work
fi
}
`
	assertScan(t, source, config, nil)
}

func TestInlineConditionalTailAllowed(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG010"}
	source := `run() {
if ready; then work; fi; finish
}
`
	assertScan(t, source, config, nil)
}

func TestInlineConditionalsClose(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG003"}
	config.MaxDepth = 2
	source := `if ready; then
work
fi
`
	assertScan(t, source, config, nil)
}

func TestInlineElifElseDoesNotReportEarlyReturn(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG009"}
	source := `run() {
if x; then return; elif y; then work; else other; fi
}
`
	assertScan(t, source, config, nil)
}

func TestInlineExitGuardAllowed(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG010"}
	source := `run() {
if failed; then return 1; fi
}
`
	assertScan(t, source, config, nil)
}

func TestInlineWrappedFunctionReported(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG010"}
	source := `run() {
if ready; then work; fi
}
`
	want := []expectedDiagnostic{
		{"LEG010", 2, 1, "Prefer a guard clause before the main path instead of wrapping function logic in an if block."},
	}
	assertScan(t, source, config, want)
}

func TestMultilineElifElseDoesNotReportEarlyReturn(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG009"}
	source := `run() {
if x; then
return
elif y; then
work
else
other
fi
}
`
	assertScan(t, source, config, nil)
}

func TestNestedGuardKeepsOuterDiagnostic(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG010"}
	source := `run() {
if ready; then
if failed; then
return 1
fi
work
fi
}
`
	want := []expectedDiagnostic{
		{"LEG010", 2, 1, "Prefer a guard clause before the main path instead of wrapping function logic in an if block."},
	}
	assertScan(t, source, config, want)
}

func TestOptionalBranchAllowed(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG010"}
	source := `run() {
if verbose; then
log
fi
work
}
`
	assertScan(t, source, config, nil)
}

func TestOptionalFinalBranchAllowed(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG010"}
	source := `run() {
work
if verbose; then
log
fi
}
`
	assertScan(t, source, config, nil)
}

func TestPhysicalFunctionLinesPreserved(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG038"}
	config.MaxFunction = 3
	source := `run() {
# context

work
# context
}
`
	want := []expectedDiagnostic{
		{"LEG038", 1, 1, "Function has 6 lines (max 3). Extract focused helper functions."},
	}
	assertScan(t, source, config, want)
}

func TestRealCasePipelineStillReported(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG001"}
	config.MaxExpression = 0
	source := `case "$answer" in
yes | no) first | second ;;
esac
`
	want := []expectedDiagnostic{
		{"LEG001", 2, 1, "Expression has 1 legibility operators (max 0). Extract named commands or values."},
	}
	assertScan(t, source, config, want)
}

func TestRealFunctionLinesStillReported(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG038"}
	config.MaxFunction = 4
	source := `run() {
first
second
third
}
`
	want := []expectedDiagnostic{
		{"LEG038", 1, 1, "Function has 5 lines (max 4). Extract focused helper functions."},
	}
	assertScan(t, source, config, want)
}

func TestSelectedLineRuleSkipsOtherAnalysis(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG001"}
	config.MaxExpression = 0
	source := `run() {
first && second
}
`
	want := []expectedDiagnostic{
		{"LEG001", 2, 1, "Expression has 1 legibility operators (max 0). Extract named commands or values."},
	}
	assertScan(t, source, config, want)
}

func TestShellOperatorsStillReported(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG001", "LEG002"}
	config.MaxExpression = 0
	source := `value="$(first && second)"
if ! ready; then
work
fi
`
	want := []expectedDiagnostic{
		{"LEG001", 1, 1, "Expression has 1 legibility operators (max 0). Extract named commands or values."},
		{"LEG002", 2, 1, "Condition has 1 legibility operators (max 0). Hoist it into a named check."},
	}
	assertScan(t, source, config, want)
}

func TestSimpleElseAfterExitReportsEarlyReturn(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG009"}
	source := `run() {
if x; then return; else other; fi
}
`
	want := []expectedDiagnostic{
		{"LEG009", 2, 1, "Avoid else after a branch exits. Return or continue early and keep the follow-up path unindented."},
	}
	assertScan(t, source, config, want)
}

func TestWrappedFunctionReported(t *testing.T) {
	config := DefaultConfig()
	config.Select = []string{"LEG010"}
	source := `run() {
if ready; then
build
upload
fi
}
`
	want := []expectedDiagnostic{
		{"LEG010", 2, 1, "Prefer a guard clause before the main path instead of wrapping function logic in an if block."},
	}
	assertScan(t, source, config, want)
}
