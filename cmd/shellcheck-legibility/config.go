package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"

	"github.com/pelletier/go-toml/v2"
	"github.com/yowainwright/shellcheck_legibility/internal/lint"
	"go.yaml.in/yaml/v3"
)

func loadConfig(options *cliOptions) (lint.Config, error) {
	config := lint.DefaultConfig()
	path := options.Config
	if path == "" {
		path = findConfig()
	}
	if path != "" {
		if err := readConfig(path, &config); err != nil {
			return config, fmt.Errorf("%s: %w", path, err)
		}
		options.Config = path
	}
	if options.Select != "" {
		config.Select = splitSelectors(options.Select)
	}
	if options.Ignore != "" {
		config.Ignore = splitSelectors(options.Ignore)
	}
	return config, nil
}

func readConfig(path string, config *lint.Config) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read configuration: %w", err)
	}
	return decodeConfig(path, data, config)
}

func findConfig() string {
	dir, err := os.Getwd()
	if err != nil {
		return ""
	}
	names := []string{".shellcheck-legibilityrc", ".shellcheck-legibility.yml", ".shellcheck-legibility.yaml", "shellcheck-legibility.toml", ".shellcheck-legibility.toml", "pyproject.toml"}
	for dir != filepath.Dir(dir) {
		for _, name := range names {
			path := filepath.Join(dir, name)
			if info, err := os.Stat(path); err == nil && info.Mode().IsRegular() {
				return path
			}
		}
		dir = filepath.Dir(dir)
	}
	return ""
}

func decodeConfig(path string, data []byte, config *lint.Config) error {
	if filepath.Base(path) == "pyproject.toml" {
		var project struct {
			Tool struct {
				Legibility *lint.Config `toml:"shellcheck-legibility"`
			} `toml:"tool"`
		}
		project.Tool.Legibility = config
		return toml.Unmarshal(data, &project)
	}
	if strings.HasSuffix(path, ".toml") {
		return toml.Unmarshal(data, config)
	}
	if strings.HasSuffix(path, "rc") && rcAssignment.Match(data) {
		return decodeRC(data, config)
	}
	return yaml.Unmarshal(data, config)
}

var rcAssignment = regexp.MustCompile(`(?m)^\s*([a-z-]+)\s*=\s*(.*)$`)

func decodeRC(data []byte, config *lint.Config) error {
	values := make(map[string]any)
	for _, match := range rcAssignment.FindAllStringSubmatch(string(data), -1) {
		key, value := match[1], strings.TrimSpace(match[2])
		parsed, err := rcValue(key, value)
		if err != nil {
			return fmt.Errorf("%s: %w", key, err)
		}
		values[key] = parsed
	}
	encoded, err := json.Marshal(values)
	if err != nil {
		return err
	}
	return json.Unmarshal(encoded, config)
}

func rcValue(key, value string) (any, error) {
	var parsed any
	if err := yaml.Unmarshal([]byte(value), &parsed); err != nil {
		return nil, err
	}
	if strings.HasPrefix(key, "max-") || strings.HasPrefix(key, "min-") {
		return strconv.Atoi(fmt.Sprint(parsed))
	}
	if list, ok := parsed.([]any); ok {
		return list, nil
	}
	if parsed == nil {
		return []string{}, nil
	}
	text := fmt.Sprint(parsed)
	if strings.HasPrefix(value, "\"") || strings.HasPrefix(value, "'") {
		return []string{text}, nil
	}
	return splitSelectors(text), nil
}

func splitSelectors(value string) []string {
	value = strings.Trim(value, "[] ")
	values := strings.Split(value, ",")
	for index, item := range values {
		values[index] = strings.Trim(item, " \t\"'")
	}
	return values
}
