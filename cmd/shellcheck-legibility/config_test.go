package main

import (
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/yowainwright/shellcheck_legibility/internal/lint"
)

func TestConfigFormats(t *testing.T) {
	cases := map[string]string{
		".shellcheck-legibilityrc":   "select=LEG,LEG041\nmax-function-lines=17\n",
		".shellcheck-legibility.yml": "select: [LEG, LEG041]\nmax-function-lines: 17\n",
		"shellcheck-legibility.toml": "select=['LEG', 'LEG041']\nmax-function-lines=17\n",
	}
	for path, source := range cases {
		t.Run(path, func(t *testing.T) {
			config := lint.DefaultConfig()
			if err := decodeConfig(path, []byte(source), &config); err != nil {
				t.Fatal(err)
			}
			if config.MaxFunction != 17 || !slices.Equal(config.Select, []string{"LEG", "LEG041"}) {
				t.Fatalf("configuration: %+v", config)
			}
		})
	}
}

func TestYAMLRetainsQuotedMatchers(t *testing.T) {
	config := lint.DefaultConfig()
	source := "comment-matchers: ['^issue#[0-9]+$', '\\bBUG\\b']\ncomment-prefix-identifiers:\n  - 'KEEP: reason'\n"
	if err := decodeConfig("config.yml", []byte(source), &config); err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(config.CommentMatchers, []string{"^issue#[0-9]+$", `\bBUG\b`}) {
		t.Fatalf("matchers: %v", config.CommentMatchers)
	}
	if !slices.Equal(config.CommentPrefixes, []string{"KEEP: reason"}) {
		t.Fatalf("prefixes: %v", config.CommentPrefixes)
	}
}

func TestPyprojectOnlyReadsLegibilitySection(t *testing.T) {
	config := lint.DefaultConfig()
	data := []byte("[tool.other]\nmax-function-lines=1\n[tool.shellcheck-legibility]\nmax-function-lines=8\nselect=['LEG035']\n")
	if err := decodeConfig("pyproject.toml", data, &config); err != nil {
		t.Fatal(err)
	}
	if config.MaxFunction != 8 || !slices.Equal(config.Select, []string{"LEG035"}) || config.MaxExpression != 4 {
		t.Fatalf("configuration: %+v", config)
	}
}

func workspaceTemp(t *testing.T) string {
	t.Helper()
	root, err := filepath.Abs("../../.build")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(root, 0755); err != nil {
		t.Fatal(err)
	}
	dir, err := os.MkdirTemp(root, "app-test-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	return dir
}
