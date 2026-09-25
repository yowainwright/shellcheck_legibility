package lint

import (
	"fmt"
	"slices"
	"strings"
)

type Diagnostic struct {
	Path     string `json:"path"`
	Line     int    `json:"line"`
	Column   int    `json:"column"`
	Code     string `json:"code"`
	Rule     string `json:"rule"`
	Message  string `json:"message"`
	trigger  int
	priority int
}

func ruleName(code string) string {
	names := map[string]string{
		"LEG001": "max-expression-operators", "LEG002": "hoist-if-operators",
		"LEG003": "max-control-flow-depth", "LEG005": "no-quadratic-patterns",
		"LEG009": "prefer-early-return", "LEG010": "prefer-guard-clauses",
		"LEG016": "require-executable-shebang", "LEG017": "no-direct-shell-bin-smoke",
		"LEG024": "prefer-object-lookup", "LEG025": "require-filename-matches-dirname",
		"LEG026": "no-mixed-filename-casing", "LEG034": "prefer-case-over-long-if-chain",
		"LEG035": "no-bool-literal-args", "LEG038": "max-function-lines",
		"LEG039": "prefer-functions", "LEG040": "use-defaults-in-functions",
		"LEG041": "no-unmatched-comments", "LEG042": "no-automated-comment-attribution",
		"LEG043": "no-stacked-comments",
	}
	return names[code]
}

func (c Config) Enabled(code string) bool {
	name := ruleName(code)
	selected := selectorMatches(c.Select, code, name)
	if code >= "LEG041" {
		selected = slices.Contains(c.Select, code) || slices.Contains(c.Select, name)
	}
	return selected && !selectorMatches(c.Ignore, code, name)
}

func selectorMatches(selectors []string, code, name string) bool {
	return slices.Contains(selectors, "LEG") || slices.Contains(selectors, "all") ||
		slices.Contains(selectors, code) || slices.Contains(selectors, name)
}

func (s *scanner) add(line, column, trigger, priority int, code, message string) {
	if !s.config.Enabled(code) || (trigger > 0 && s.ignored(line, code)) {
		return
	}
	key := fmt.Sprintf("%d:%s", line, code)
	if s.reported[key] {
		return
	}
	s.reported[key] = true
	d := Diagnostic{s.path, line, column, code, ruleName(code), message, trigger, priority}
	s.diagnostics = append(s.diagnostics, d)
}

func (s *scanner) ignored(line int, code string) bool {
	if line < 1 || line > len(s.lines) {
		return false
	}
	raw := s.lines[line-1]
	return strings.Contains(raw, "noqa") && (strings.Contains(raw, code) || strings.Contains(raw, "LEG"))
}
