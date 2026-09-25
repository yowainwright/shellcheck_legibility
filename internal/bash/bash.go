package bash

import (
	"bytes"
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"

	"github.com/yowainwright/shellcheck_legibility/internal/lint"
)

//go:embed defaults.bash util.bash rules.bash config.bash cli.bash files.bash cache.bash lint.bash output.bash
var sources embed.FS

func Check(args []string) ([]lint.Diagnostic, error) {
	var stdout, stderr bytes.Buffer
	status := Run(args, &stdout, &stderr)
	if status != 0 && status != 1 {
		return nil, fmt.Errorf("Bash compatibility check: %s", strings.TrimSpace(stderr.String()))
	}
	var diagnostics []lint.Diagnostic
	if err := json.Unmarshal(stdout.Bytes(), &diagnostics); err != nil {
		return nil, fmt.Errorf("Bash compatibility output: %w", err)
	}
	return diagnostics, nil
}

func Run(args []string, stdout, stderr io.Writer) int {
	command, err := newCommand(args)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 2
	}
	command.Stdout, command.Stderr = stdout, stderr
	if err := command.Run(); err != nil {
		if command.ProcessState != nil && command.ProcessState.ExitCode() > 0 {
			return command.ProcessState.ExitCode()
		}
		fmt.Fprintf(stderr, "Bash is required for compatibility scanning: %v\n", err)
		return 2
	}
	return 0
}

func newCommand(args []string) (*exec.Cmd, error) {
	source, err := script()
	if err != nil {
		return nil, err
	}
	executable, err := os.Executable()
	if err != nil {
		return nil, err
	}
	arguments := append([]string{"/dev/stdin"}, args...)
	command := exec.Command("bash", arguments...)
	command.Env = append(os.Environ(), "SHELLCHECK_LEGIBILITY_BINARY="+executable)
	command.Stdin = strings.NewReader(source)
	return command, nil
}

func script() (string, error) {
	var source strings.Builder
	source.WriteString("set -u -o pipefail\n")
	modules := []string{"defaults", "util", "rules", "config", "cli", "files", "cache", "lint", "output"}
	for _, module := range modules {
		data, err := sources.ReadFile(module + ".bash")
		if err != nil {
			return "", err
		}
		source.Write(data)
		source.WriteByte('\n')
	}
	source.WriteString("CACHE_SOURCES=(\"$SHELLCHECK_LEGIBILITY_BINARY\")\nmain \"$@\"\n")
	return source.String(), nil
}
