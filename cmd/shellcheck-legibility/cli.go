package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/yowainwright/shellcheck_legibility/internal/lint"
)

type cliOptions struct {
	Paths    []string
	Config   string
	Format   string
	Select   string
	Ignore   string
	CacheDir string
	ExitZero bool
	Version  bool
	Help     bool
}

func parseOptions(args []string) (cliOptions, error) {
	o := cliOptions{Format: "text", CacheDir: os.Getenv("SHELLCHECK_LEGIBILITY_CACHE_DIR")}
	if len(args) > 0 && args[0] == "check" {
		args = args[1:]
	}
	for len(args) > 0 {
		remaining, err := o.consumeOption(args)
		if err != nil {
			return o, err
		}
		args = remaining
	}
	if o.Format != "text" && o.Format != "json" {
		return o, fmt.Errorf("output format must be text or json")
	}
	return o, nil
}

func (o *cliOptions) consumeOption(args []string) ([]string, error) {
	arg, value, inline := strings.Cut(args[0], "=")
	consumed := 1
	if takesValue(arg) && !inline {
		if len(args) < 2 {
			return nil, fmt.Errorf("%s requires a value", arg)
		}
		value, consumed = args[1], 2
	}
	return args[consumed:], o.applyOption(arg, value, args[0])
}

func takesValue(option string) bool {
	switch option {
	case "--config", "--output-format", "--select", "--ignore":
		return true
	}
	return false
}

func (o *cliOptions) applyOption(arg, value, original string) error {
	if !strings.HasPrefix(arg, "-") {
		o.Paths = append(o.Paths, original)
		return nil
	}
	if takesValue(arg) {
		o.applyValue(arg, value)
		return nil
	}
	return o.applyFlag(arg)
}

func (o *cliOptions) applyValue(arg, value string) {
	switch arg {
	case "--config":
		o.Config = value
	case "--output-format":
		o.Format = value
	case "--select":
		o.Select = value
	case "--ignore":
		o.Ignore = value
	}
}

func (o *cliOptions) applyFlag(arg string) error {
	switch arg {
	case "--cache":
		o.enableCache()
	case "--no-cache":
		o.CacheDir = ""
	case "--exit-zero":
		o.ExitZero = true
	case "--version":
		o.Version = true
	case "-h", "--help":
		o.Help = true
	default:
		return fmt.Errorf("unknown option: %s", arg)
	}
	return nil
}

func (o *cliOptions) enableCache() {
	if o.CacheDir != "" {
		return
	}
	root := os.Getenv("XDG_CACHE_HOME")
	if root == "" {
		home, _ := os.UserHomeDir()
		root = filepath.Join(home, ".cache")
	}
	o.CacheDir = filepath.Join(root, "shellcheck-legibility")
}

type fallbackScanner func(string, cliOptions) ([]lint.Diagnostic, error)

func runCLI(args []string, stdout, stderr io.Writer, version string, fallback fallbackScanner) int {
	status, err := run(args, stdout, version, fallback)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 2
	}
	return status
}

func run(args []string, stdout io.Writer, version string, fallback fallbackScanner) (int, error) {
	options, err := parseOptions(args)
	if err != nil {
		return 2, err
	}
	if options.Version {
		fmt.Fprintln(stdout, version)
		return 0, nil
	}
	if options.Help {
		usage(stdout)
		return 0, nil
	}
	return runCheck(options, stdout, fallback)
}

func runCheck(options cliOptions, stdout io.Writer, fallback fallbackScanner) (int, error) {
	config, err := loadConfig(&options)
	if err != nil {
		return 2, err
	}
	paths, err := expandTargets(options.Paths, config)
	if err != nil {
		return 2, err
	}
	findings, err := checkPaths(paths, options, config, fallback)
	writeErr := writeDiagnostics(stdout, findings, options.Format)
	if err != nil {
		return 2, errors.Join(err, writeErr)
	}
	if len(findings) != 0 && !options.ExitZero {
		return 1, writeErr
	}
	return 0, writeErr
}

func usage(writer io.Writer) {
	fmt.Fprintln(writer, "Usage: shellcheck-legibility check [paths...] [options]")
	fmt.Fprintln(writer, "  --config PATH --select RULES --ignore RULES --output-format text|json")
	fmt.Fprintln(writer, "  --cache       Reuse unchanged file results; --no-cache forces a full scan.")
	fmt.Fprintln(writer, "  SHELLCHECK_LEGIBILITY_CACHE_DIR sets and enables the session cache.")
}

func checkPaths(paths []string, options cliOptions, config lint.Config, fallback fallbackScanner) ([]lint.Diagnostic, error) {
	cache := newCache(options.CacheDir, config)
	findings := []lint.Diagnostic{}
	var failures []error
	for _, path := range paths {
		result, err := checkFile(path, options, config, fallback, cache)
		if err != nil {
			failures = append(failures, fmt.Errorf("%s: %w", path, err))
			continue
		}
		findings = append(findings, result...)
	}
	return findings, errors.Join(failures...)
}

func checkFile(path string, options cliOptions, config lint.Config, fallback fallbackScanner, cache resultCache) ([]lint.Diagnostic, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	key := cache.key(path)
	if saved, ok := cache.read(key, data); ok {
		return saved, nil
	}
	result, err := lint.Scan(path, data, config)
	if err != nil && fallback != nil {
		return fallback(path, options)
	}
	if err == nil {
		cache.write(key, data, result)
	}
	return result, err
}

func writeDiagnostics(writer io.Writer, diagnostics []lint.Diagnostic, format string) error {
	if format == "json" {
		return writeJSON(writer, diagnostics)
	}
	for _, d := range diagnostics {
		if _, err := fmt.Fprintf(writer, "%s:%d:%d: %s %s\n", d.Path, d.Line, d.Column, d.Code, d.Message); err != nil {
			return err
		}
	}
	return nil
}

func writeJSON(writer io.Writer, diagnostics []lint.Diagnostic) error {
	if _, err := fmt.Fprintln(writer, "["); err != nil {
		return err
	}
	for index, diagnostic := range diagnostics {
		if index > 0 {
			if _, err := fmt.Fprintln(writer, ","); err != nil {
				return err
			}
		}
		encoded, err := json.Marshal(diagnostic)
		if err != nil {
			return err
		}
		if _, err := fmt.Fprintf(writer, "  %s", encoded); err != nil {
			return err
		}
	}
	_, err := fmt.Fprintln(writer, "\n]")
	return err
}
