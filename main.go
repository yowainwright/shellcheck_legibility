package main

import (
	"embed"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/yowainwright/shellcheck_legibility/internal/app"
	"github.com/yowainwright/shellcheck_legibility/internal/lint"
)

//go:embed lib/*.bash
var legacySources embed.FS

var version = "0.2.1"

func main() {
	os.Exit(app.Run(os.Args[1:], os.Stdout, os.Stderr, version, legacyScan))
}

func legacyScan(path string, options app.Options) ([]lint.Diagnostic, error) {
	script, err := legacyScript()
	if err != nil {
		return nil, err
	}
	command := exec.Command("bash", legacyArgs(path, options)...)
	command.Stdin = strings.NewReader(script)
	output, err := command.Output()
	if err != nil && (command.ProcessState == nil || command.ProcessState.ExitCode() != 1) {
		return nil, fmt.Errorf("Bash compatibility check: %w", err)
	}
	var diagnostics []lint.Diagnostic
	if err := json.Unmarshal(output, &diagnostics); err != nil {
		return nil, fmt.Errorf("Bash compatibility output: %w", err)
	}
	return diagnostics, nil
}

func legacyArgs(path string, options app.Options) []string {
	args := []string{"/dev/stdin", "check", path, "--output-format", "json", "--no-cache"}
	if options.Config != "" {
		args = append(args, "--config", options.Config)
	}
	if options.Select != "" {
		args = append(args, "--select", options.Select)
	}
	if options.Ignore != "" {
		args = append(args, "--ignore", options.Ignore)
	}
	return args
}

func legacyScript() (string, error) {
	var script strings.Builder
	script.WriteString("set -u -o pipefail\n")
	modules := []string{"defaults", "util", "rules", "config", "cli", "files", "cache", "lint", "output"}
	for _, module := range modules {
		data, err := legacySources.ReadFile("lib/" + module + ".bash")
		if err != nil {
			return "", err
		}
		script.Write(data)
		script.WriteByte('\n')
	}
	script.WriteString("main \"$@\"\n")
	return script.String(), nil
}
