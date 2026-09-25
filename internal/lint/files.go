package lint

import (
	"fmt"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"unicode"

	"mvdan.cc/sh/v3/pattern"
)

func (s *scanner) checkFiles() {
	first := strings.TrimPrefix(s.lines[0], "#!")
	validShebang := strings.HasPrefix(s.lines[0], "#!") && runtimeAllowed(first, s.config.Runtimes)
	if matchesAny(s.path, s.config.ExecutableEntries) && !validShebang {
		s.add(1, 1, 0, 0, "LEG016", "Executable shell entry file has no accepted shebang.")
	}
	s.checkFilename()
	base := strings.SplitN(strings.TrimPrefix(filepath.Base(s.path), "."), ".", 2)[0]
	if mixedCasing(base) {
		s.add(1, 1, 0, 2, "LEG026", "Filename \""+base+"\" mixes casing conventions. Use one casing convention.")
	}
}

func (s *scanner) checkFilename() {
	depth := strings.Count(strings.TrimPrefix(s.path, "./"), "/")
	if depth < s.config.MinDirname {
		return
	}
	parent := filepath.Base(filepath.Dir(s.path))
	file := strings.TrimSuffix(filepath.Base(s.path), filepath.Ext(s.path))
	base := strings.SplitN(file, ".", 2)[0]
	if base == parent || standaloneFilename(base) {
		return
	}
	message := fmt.Sprintf("Filename %q does not match parent directory %q.", file, parent)
	s.add(1, 1, 0, 1, "LEG025", message)
}

func standaloneFilename(name string) bool {
	return slices.Contains([]string{"index", "constants", "helpers", "utils"}, name)
}

func mixedCasing(name string) bool {
	hyphen, underscore := strings.Contains(name, "-"), strings.Contains(name, "_")
	upper, lower := false, false
	for _, char := range name {
		upper = upper || unicode.IsUpper(char)
		lower = lower || unicode.IsLower(char)
	}
	return (hyphen && underscore) || ((hyphen || underscore) && upper && lower)
}

func runtimeAllowed(command string, runtimes []string) bool {
	command = strings.TrimSpace(command)
	command = strings.TrimPrefix(command, "/usr/bin/env ")
	command = strings.TrimRight(command, "/")
	return slices.Contains(runtimes, filepath.Base(command))
}

func matchesAny(path string, patterns []string) bool {
	path = strings.TrimPrefix(path, "./")
	for _, glob := range patterns {
		expression, err := pattern.Regexp(glob, pattern.EntireString)
		if err != nil {
			continue
		}
		matched, err := regexp.MatchString(expression, path)
		if err == nil && matched {
			return true
		}
	}
	return false
}
