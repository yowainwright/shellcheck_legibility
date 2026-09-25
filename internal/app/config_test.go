package app

import (
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/yowainwright/shellcheck_legibility/internal/lint"
)

func TestExistingConfigFormats(t *testing.T) {
	cases := map[string]int{
		"rc/.shellcheck-legibilityrc":     17,
		"yaml/.shellcheck-legibility.yml": 18,
		"toml/shellcheck-legibility.toml": 19,
	}
	for path, lines := range cases {
		t.Run(path, func(t *testing.T) {
			options := Options{Config: filepath.Join("../../tests/fixtures/config", path)}
			config, err := loadConfig(&options)
			if err != nil {
				t.Fatal(err)
			}
			if config.MaxFunction != lines || !slices.Equal(config.Select, []string{"LEG", "LEG041"}) {
				t.Fatalf("configuration: %+v", config)
			}
		})
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
