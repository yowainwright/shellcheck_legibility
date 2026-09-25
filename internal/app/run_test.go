package app

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
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

func TestDiscoveryExcludesBuildAndKeepsShellScripts(t *testing.T) {
	dir := workspaceTemp(t)
	t.Chdir(dir)
	if err := os.MkdirAll(".build/nested", 0755); err != nil {
		t.Fatal(err)
	}
	writeTestFile(t, ".build/nested/generated.sh", "echo true")
	writeTestFile(t, "example.sh", "run() { :; }")
	writeTestFile(t, "command", "#!/usr/bin/env bash\nrun() { :; }")
	writeTestFile(t, "readme.md", "text")
	paths, err := expandTargets(nil, lint.DefaultConfig())
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(paths, ",") != "./command,./example.sh" {
		t.Fatalf("discovered: %v", paths)
	}
}

func TestIncompleteSourceIsNeverCached(t *testing.T) {
	dir := workspaceTemp(t)
	t.Chdir(dir)
	writeTestFile(t, "broken.sh", "run() { create_user true;\n")
	options := Options{CacheDir: filepath.Join(dir, "cache")}
	calls := 0
	legacy := func(string, Options) ([]lint.Diagnostic, error) { calls++; return nil, nil }
	for range 2 {
		if _, err := checkPaths([]string{"broken.sh"}, options, lint.DefaultConfig(), legacy); err != nil {
			t.Fatal(err)
		}
	}
	if calls != 2 {
		t.Fatalf("compatibility scanner called %d times", calls)
	}
}

func TestCacheRejectsIncompleteRecords(t *testing.T) {
	dir := workspaceTemp(t)
	cache := newCache(dir, lint.DefaultConfig())
	key := cache.key("example.sh", []byte("run() { :; }"))
	writeTestFile(t, filepath.Join(dir, key), `{"Key":"`+key+`"}`)
	if _, hit := cache.read(key); hit {
		t.Fatal("incomplete record accepted")
	}
	cache.write(key, nil)
	if findings, hit := cache.read(key); !hit || len(findings) != 0 {
		t.Fatal("clean result was not cached")
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
	status := Run(args, &output, &output, "test", nil)
	return status, output.String()
}
