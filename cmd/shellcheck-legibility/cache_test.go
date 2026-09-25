package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/yowainwright/shellcheck_legibility/internal/lint"
)

func TestIncompleteSourceIsNeverCached(t *testing.T) {
	dir := workspaceTemp(t)
	t.Chdir(dir)
	writeTestFile(t, "broken.sh", "run() { create_user true;\n")
	options := cliOptions{CacheDir: filepath.Join(dir, "cache")}
	calls := 0
	fallback := func(string, cliOptions) ([]lint.Diagnostic, error) { calls++; return nil, nil }
	for range 2 {
		if _, err := checkPaths([]string{"broken.sh"}, options, lint.DefaultConfig(), fallback); err != nil {
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
	source := []byte("run() { :; }")
	key := cache.key("example.sh")
	writeTestFile(t, filepath.Join(dir, key), `{"Key":"`+key+`"}`)
	if _, hit := cache.read(key, source); hit {
		t.Fatal("incomplete record accepted")
	}
	cache.write(key, source, nil)
	if findings, hit := cache.read(key, source); !hit || len(findings) != 0 {
		t.Fatal("clean result was not cached")
	}
}

func TestEditsReplaceCachedResult(t *testing.T) {
	dir := workspaceTemp(t)
	cache := newCache(dir, lint.DefaultConfig())
	key := cache.key("example.sh")
	for _, source := range []string{"create_user true", "create_user name", "create_user false"} {
		if _, hit := cache.read(key, []byte(source)); hit {
			t.Fatal("edited source reused stale diagnostics")
		}
		cache.write(key, []byte(source), nil)
		if _, hit := cache.read(key, []byte(source)); !hit {
			t.Fatal("unchanged source missed cache")
		}
	}
	entries, err := os.ReadDir(dir)
	if err != nil || len(entries) != 1 {
		t.Fatalf("expected one cache entry after edits: %v, %v", entries, err)
	}
}
