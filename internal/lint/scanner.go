package lint

import (
	"bytes"
	"cmp"
	"slices"
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

type scanner struct {
	path        string
	config      Config
	source      []byte
	code        []byte
	lines       []string
	diagnostics []Diagnostic
	reported    map[string]bool
	comments    []*syntax.Comment
}

func Scan(path string, source []byte, config Config) ([]Diagnostic, error) {
	s := scanner{path: path, config: config, source: source, code: bytes.Clone(source)}
	s.lines = strings.Split(string(source), "\n")
	s.reported = make(map[string]bool)
	parser := syntax.NewParser(syntax.KeepComments(true), syntax.Variant(language(path, source)))
	file, err := parser.Parse(bytes.NewReader(source), path)
	if err != nil {
		return nil, err
	}
	s.prepareCode(file)
	s.checkFiles()
	s.checkComments()
	s.checkLines()
	s.checkStructure(file)
	s.checkTopLevel(file)
	slices.SortStableFunc(s.diagnostics, compareDiagnostics)
	return s.diagnostics, nil
}

func language(path string, source []byte) syntax.LangVariant {
	first, _, _ := bytes.Cut(source, []byte("\n"))
	if strings.HasSuffix(path, ".zsh") || bytes.HasSuffix(first, []byte("zsh")) {
		return syntax.LangZsh
	}
	if strings.HasSuffix(path, ".ksh") || bytes.HasSuffix(first, []byte("ksh")) {
		return syntax.LangMirBSDKorn
	}
	return syntax.LangBash
}

func compareDiagnostics(a, b Diagnostic) int {
	if order := cmp.Compare(a.trigger, b.trigger); order != 0 {
		return order
	}
	return cmp.Compare(a.priority, b.priority)
}

func (s *scanner) prepareCode(file *syntax.File) {
	syntax.Walk(file, s.maskNode)
	s.maskEscapes()
}

func (s *scanner) maskNode(node syntax.Node) bool {
	switch n := node.(type) {
	case *syntax.Comment:
		s.comments = append(s.comments, n)
		s.mask(n, false)
	case *syntax.SglQuoted:
		s.mask(n, true)
		return false
	case *syntax.DblQuoted:
		s.mask(n, true)
		s.restoreSubstitutions(n)
	case *syntax.Redirect:
		return s.maskHeredoc(n)
	case *syntax.CaseItem:
		s.maskCasePatterns(n.Patterns)
	}
	return true
}

func (s *scanner) maskHeredoc(redirect *syntax.Redirect) bool {
	if redirect.Hdoc == nil {
		return true
	}
	s.mask(redirect.Hdoc, false)
	return false
}

func (s *scanner) maskCasePatterns(patterns []*syntax.Word) {
	if len(patterns) == 0 {
		return
	}
	start, end := patterns[0].Pos().Offset(), patterns[len(patterns)-1].End().Offset()
	for index := start; index < end; index++ {
		if s.code[index] != '\n' {
			s.code[index] = ' '
		}
	}
	for _, word := range patterns {
		s.restoreSubstitutions(word)
	}
}

func (s *scanner) mask(node syntax.Node, marker bool) {
	start, end := int(node.Pos().Offset()), int(node.End().Offset())
	for index := start; index < end && index < len(s.code); index++ {
		if s.code[index] != '\n' {
			s.code[index] = ' '
		}
	}
	if marker && start < len(s.code) {
		s.code[start] = 'x'
	}
}

func (s *scanner) restoreSubstitutions(node syntax.Node) {
	syntax.Walk(node, func(child syntax.Node) bool {
		substitution, ok := child.(*syntax.CmdSubst)
		if !ok {
			return true
		}
		start, end := substitution.Pos().Offset(), substitution.End().Offset()
		copy(s.code[start:end], s.source[start:end])
		return false
	})
}

func (s *scanner) maskEscapes() {
	for index := 0; index+1 < len(s.code); index++ {
		if s.code[index] != '\\' {
			continue
		}
		s.code[index] = 'x'
		index++
		if s.code[index] != '\n' {
			s.code[index] = ' '
		}
	}
}

func (s *scanner) text(node syntax.Node) string {
	return string(s.source[node.Pos().Offset():node.End().Offset()])
}

func firstWord(line string) string {
	words := strings.Fields(line)
	if len(words) == 0 {
		return ""
	}
	return words[0]
}
