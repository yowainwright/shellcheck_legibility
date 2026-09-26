package main

import (
	"os"

	"github.com/yowainwright/shellcheck_legibility/internal/bash"
)

var version = "0.2.1"

func main() {
	if os.Getenv("SHELLCHECK_LEGIBILITY_ENGINE") == "bash" {
		os.Exit(bash.Run(os.Args[1:], os.Stdout, os.Stderr, version))
	}
	os.Exit(runCLI(os.Args[1:], os.Stdout, os.Stderr, version))
}
