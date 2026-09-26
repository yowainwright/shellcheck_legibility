package bash

import (
	"embed"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
)

//go:embed defaults.bash util.bash rules.bash config.bash cli.bash files.bash cache.bash lint.bash output.bash
var sources embed.FS

func Run(args []string, stdout, stderr io.Writer, version string) int {
	command, err := newCommand(args, version)
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

func newCommand(args []string, version string) (*exec.Cmd, error) {
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
	command.Env = append(os.Environ(),
		"SHELLCHECK_LEGIBILITY_BINARY="+executable,
		"SHELLCHECK_LEGIBILITY_VERSION="+version,
	)
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
