package main

import (
	"os"

	"github.com/yowainwright/shellcheck_legibility/internal/bash"
	"github.com/yowainwright/shellcheck_legibility/internal/lint"
)

var version = "0.2.1"

func main() {
	if os.Getenv("SHELLCHECK_LEGIBILITY_ENGINE") == "bash" {
		os.Exit(bash.Run(os.Args[1:], os.Stdout, os.Stderr, version))
	}
	os.Exit(runCLI(os.Args[1:], os.Stdout, os.Stderr, version, scanWithBash))
}

func scanWithBash(path string, options cliOptions) ([]lint.Diagnostic, error) {
	args := []string{"check", path, "--output-format", "json", "--no-cache"}
	if options.Config != "" {
		args = append(args, "--config", options.Config)
	}
	if options.Select != "" {
		args = append(args, "--select", options.Select)
	}
	if options.Ignore != "" {
		args = append(args, "--ignore", options.Ignore)
	}
	return bash.Check(args, version)
}
