package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/yowainwright/shellcheck_legibility/internal/lint"
)

func TestMalformedSourceIsNeverCached(t *testing.T) {
	dir := workspaceTemp(t)
	t.Chdir(dir)
	writeTestFile(t, "broken.sh", "unexpected)\n")
	options := cliOptions{CacheDir: filepath.Join(dir, "cache")}
	for range 2 {
		if _, err := checkPaths([]string{"broken.sh"}, options, lint.DefaultConfig()); err == nil {
			t.Fatal("malformed source did not return an error")
		}
	}
	entries, err := os.ReadDir(options.CacheDir)
	if err != nil || len(entries) != 0 {
		t.Fatalf("malformed source was cached: %v, %v", entries, err)
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
