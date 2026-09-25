package app

import (
	"encoding/json"
	"fmt"
	"io"
	"os"

	"github.com/yowainwright/shellcheck_legibility/internal/lint"
)

type LegacyScan func(string, Options) ([]lint.Diagnostic, error)

func Run(args []string, stdout, stderr io.Writer, version string, legacy LegacyScan) int {
	status, err := run(args, stdout, version, legacy)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 2
	}
	return status
}

func run(args []string, stdout io.Writer, version string, legacy LegacyScan) (int, error) {
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
	return runCheck(options, stdout, legacy)
}

func runCheck(options Options, stdout io.Writer, legacy LegacyScan) (int, error) {
	config, err := loadConfig(&options)
	if err != nil {
		return 2, err
	}
	paths, err := expandTargets(options.Paths, config)
	if err != nil {
		return 2, err
	}
	findings, err := checkPaths(paths, options, config, legacy)
	if err != nil {
		return 2, err
	}
	err = writeDiagnostics(stdout, findings, options.Format)
	if len(findings) != 0 && !options.ExitZero {
		return 1, err
	}
	return 0, err
}

func usage(writer io.Writer) {
	fmt.Fprintln(writer, "Usage: shellcheck-legibility check [paths...] [options]")
	fmt.Fprintln(writer, "  --config PATH --select RULES --ignore RULES --output-format text|json")
	fmt.Fprintln(writer, "  --cache       Reuse unchanged file results; --no-cache forces a full scan.")
	fmt.Fprintln(writer, "  SHELLCHECK_LEGIBILITY_CACHE_DIR sets and enables the session cache.")
}

func checkPaths(paths []string, options Options, config lint.Config, legacy LegacyScan) ([]lint.Diagnostic, error) {
	cache := newCache(options.CacheDir, config)
	findings := []lint.Diagnostic{}
	for _, path := range paths {
		result, err := checkFile(path, options, config, legacy, cache)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", path, err)
		}
		findings = append(findings, result...)
	}
	return findings, nil
}

func checkFile(path string, options Options, config lint.Config, legacy LegacyScan, cache resultCache) ([]lint.Diagnostic, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	key := cache.key(path, data)
	if saved, ok := cache.read(key); ok {
		return saved, nil
	}
	result, err := lint.Scan(path, data, config)
	if err != nil && legacy != nil {
		return legacy(path, options)
	}
	if err == nil {
		cache.write(key, result)
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
