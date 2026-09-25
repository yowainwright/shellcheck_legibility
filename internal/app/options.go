package app

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type Options struct {
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

func parseOptions(args []string) (Options, error) {
	o := Options{Format: "text", CacheDir: os.Getenv("SHELLCHECK_LEGIBILITY_CACHE_DIR")}
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

func (o *Options) consumeOption(args []string) ([]string, error) {
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

func (o *Options) applyOption(arg, value, original string) error {
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

func (o *Options) applyValue(arg, value string) {
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

func (o *Options) applyFlag(arg string) error {
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

func (o *Options) enableCache() {
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
