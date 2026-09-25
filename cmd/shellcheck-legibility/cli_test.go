package main

import (
	"bytes"
	"encoding/json"
	"os"
	"testing"

	"github.com/yowainwright/shellcheck_legibility/internal/lint"
)

func TestCLIOptionsAndDiagnostics(t *testing.T) {
	dir := workspaceTemp(t)
	t.Chdir(dir)
	writeTestFile(t, "example.sh", "run() { create_user true; }\n")
	writeTestFile(t, "config.yml", "select: [LEG038]\n")
	args := []string{"check", "example.sh", "--config", "config.yml", "--select", "LEG035", "--output-format=json", "--no-cache"}
	status, output := runTestCLI(args)
	var findings []lint.Diagnostic
	if err := json.Unmarshal([]byte(output), &findings); err != nil {
		t.Fatal(err)
	}
	if status != 1 || len(findings) != 1 || findings[0].Code != "LEG035" {
		t.Fatalf("status %d: %s", status, output)
	}
	assertSuccessfulCLI(t, append(args, "--exit-zero"))
	assertSuccessfulCLI(t, append(args, "--ignore=LEG035"))
}

func assertSuccessfulCLI(t *testing.T, args []string) {
	t.Helper()
	if status, output := runTestCLI(args); status != 0 {
		t.Fatalf("status %d: %s", status, output)
	}
}

func TestCLIReportsErrors(t *testing.T) {
	t.Chdir(workspaceTemp(t))
	for _, args := range [][]string{{"--config"}, {"--unknown"}, {"--output-format=xml"}, {"missing.sh"}, {"--config=missing.yml"}} {
		if status, _ := runTestCLI(args); status != 2 {
			t.Errorf("%v: status %d", args, status)
		}
	}
}

func writeTestFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
}

func runTestCLI(args []string) (int, string) {
	var output bytes.Buffer
	status := runCLI(args, &output, &output, "test", nil)
	return status, output.String()
}
