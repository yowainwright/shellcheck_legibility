package lint

import (
	"regexp"
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

var bareArgument = regexp.MustCompile(`(^|[^\\])\$[1-9][0-9]*`)
var bracedArgument = regexp.MustCompile(`\$\{([1-9][0-9]*)([^}]*)\}`)

func (s *scanner) checkArgumentBinding(assignment *syntax.Assign, parent syntax.Node) {
	if !bindingParent(parent) {
		return
	}
	text := s.text(assignment)
	if !unguardedArgument(text) {
		return
	}
	line := int(assignment.Pos().Line())
	s.add(line, 1, line, 60, "LEG040", "Use a default or required-argument expansion when binding positional parameters inside functions.")
}

func bindingParent(parent syntax.Node) bool {
	declaration, ok := parent.(*syntax.DeclClause)
	if !ok {
		return true
	}
	command := declaration.Variant.Value
	if command != "local" && command != "declare" && command != "typeset" {
		return false
	}
	return !globalDeclaration(declaration)
}

func globalDeclaration(declaration *syntax.DeclClause) bool {
	for _, assignment := range declaration.Args {
		if assignment.Name != nil {
			break
		}
		if assignment.Value == nil {
			continue
		}
		word := assignment.Value.Lit()
		if strings.HasPrefix(word, "-") && strings.Contains(word, "g") {
			return true
		}
	}
	return false
}

func unguardedArgument(text string) bool {
	if bareArgument.MatchString(text) {
		return true
	}
	for _, match := range bracedArgument.FindAllStringSubmatch(text, -1) {
		suffix := strings.TrimPrefix(match[2], ":")
		if strings.HasPrefix(suffix, "-") || strings.HasPrefix(suffix, "=") || strings.HasPrefix(suffix, "?") {
			continue
		}
		return true
	}
	return false
}
