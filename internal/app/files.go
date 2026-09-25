package app

import (
	"bufio"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/yowainwright/shellcheck_legibility/internal/lint"
)

func expandTargets(targets []string, config lint.Config) ([]string, error) {
	if len(targets) == 0 {
		targets = []string{"."}
	}
	var paths []string
	for _, target := range targets {
		found, err := expandTarget(target, config)
		if err != nil {
			return nil, err
		}
		paths = append(paths, found...)
	}
	return paths, nil
}

func expandTarget(target string, config lint.Config) ([]string, error) {
	info, err := os.Stat(target)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", target, err)
	}
	if info.IsDir() {
		return walkShellFiles(target, config)
	}
	if info.Mode().IsRegular() && shellFile(target, config) {
		return []string{target}, nil
	}
	return nil, nil
}

func walkShellFiles(root string, config lint.Config) ([]string, error) {
	var paths []string
	err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		omit := excluded(path, config.Exclude)
		if entry.IsDir() && omit {
			return filepath.SkipDir
		}
		if omit || !entry.Type().IsRegular() || !shellFile(path, config) {
			return nil
		}
		paths = append(paths, displayPath(root, path))
		return nil
	})
	return paths, err
}

func displayPath(root, path string) string {
	if root == "." || strings.HasPrefix(root, "./") {
		return "./" + path
	}
	return path
}

func excluded(path string, excludes []string) bool {
	for _, item := range excludes {
		if path == item || strings.HasSuffix(path, "/"+item) || strings.HasPrefix(path, "./"+item+"/") || strings.Contains(path, "/"+item+"/") {
			return true
		}
	}
	return false
}

func shellFile(path string, config lint.Config) bool {
	if slices.Contains([]string{".sh", ".bash", ".zsh", ".ksh"}, filepath.Ext(path)) {
		return true
	}
	file, err := os.Open(path)
	if err != nil {
		return false
	}
	defer file.Close()
	reader := bufio.NewReader(file)
	bytes, _ := reader.ReadSlice('\n')
	line := string(bytes)
	if !strings.HasPrefix(line, "#!") {
		return false
	}
	command := strings.TrimSpace(strings.TrimPrefix(line, "#!"))
	command = strings.TrimPrefix(command, "/usr/bin/env ")
	return slices.Contains(config.Runtimes, filepath.Base(strings.TrimRight(command, "/")))
}
