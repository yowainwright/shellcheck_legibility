package main

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/yowainwright/shellcheck_legibility/internal/lint"
)

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

func TestOverlappingTargetsAreScannedOnce(t *testing.T) {
	dir := workspaceTemp(t)
	t.Chdir(dir)
	writeTestFile(t, "example.sh", "run() { :; }")
	targets := []string{"example.sh", ".", "./example.sh", filepath.Join(dir, "example.sh")}
	paths, err := expandTargets(targets, lint.DefaultConfig())
	if err != nil || !slices.Equal(paths, []string{"example.sh"}) {
		t.Fatalf("discovered: %v, %v", paths, err)
	}
}

func TestDirectoryWalkSkipsSymlinks(t *testing.T) {
	t.Chdir(workspaceTemp(t))
	writeTestFile(t, "example.sh", "run() { :; }")
	for link, target := range map[string]string{"alias.sh": "example.sh", "loop": ".", "broken.sh": "missing.sh"} {
		if err := os.Symlink(target, link); err != nil {
			t.Fatal(err)
		}
	}
	paths, err := expandTargets([]string{"."}, lint.DefaultConfig())
	if err != nil || !slices.Equal(paths, []string{"./example.sh"}) {
		t.Fatalf("discovered: %v, %v", paths, err)
	}
	paths, err = expandTargets([]string{"alias.sh"}, lint.DefaultConfig())
	if err != nil || !slices.Equal(paths, []string{"alias.sh"}) {
		t.Fatalf("explicit symlink: %v, %v", paths, err)
	}
}

func TestExclusionsPreserveBashPathMatching(t *testing.T) {
	cases := []struct {
		path, exclude string
		want          bool
	}{
		{"example.sh", "example.sh", true},
		{"./example.sh", "example.sh", false},
		{"src/example.sh", "example.sh", false},
		{"src/example.sh", "src/example.sh", true},
		{"./vendor/example.sh", "vendor", true},
		{"src/vendor/example.sh", "vendor", true},
		{"src/vendor-copy/example.sh", "vendor", false},
	}
	for _, tc := range cases {
		if got := excluded(tc.path, []string{tc.exclude}); got != tc.want {
			t.Errorf("excluded(%q, %q) = %v, want %v", tc.path, tc.exclude, got, tc.want)
		}
	}
}

func TestExplicitFilesBypassDirectoryExclusions(t *testing.T) {
	t.Chdir(workspaceTemp(t))
	writeTestFile(t, "example.sh", "run() { :; }")
	config := lint.DefaultConfig()
	config.Exclude = []string{"./example.sh"}
	paths, err := expandTargets([]string{"."}, config)
	if err != nil || len(paths) != 0 {
		t.Fatalf("excluded file: %v, %v", paths, err)
	}
	paths, err = expandTargets([]string{"./example.sh"}, config)
	if err != nil || !slices.Equal(paths, []string{"./example.sh"}) {
		t.Fatalf("explicit file: %v, %v", paths, err)
	}
}
