package lint

import (
	"bytes"
	"cmp"
	"fmt"
	"slices"
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

type Config struct {
	Select               []string `json:"select" yaml:"select" toml:"select"`
	Ignore               []string `json:"ignore" yaml:"ignore" toml:"ignore"`
	Exclude              []string `json:"exclude" yaml:"exclude" toml:"exclude"`
	ExecutableEntries    []string `json:"executable-entry-patterns" yaml:"executable-entry-patterns" toml:"executable-entry-patterns"`
	DirectEntries        []string `json:"direct-shell-entry-patterns" yaml:"direct-shell-entry-patterns" toml:"direct-shell-entry-patterns"`
	Runtimes             []string `json:"executable-runtimes" yaml:"executable-runtimes" toml:"executable-runtimes"`
	CommentMatchers      []string `json:"comment-matchers" yaml:"comment-matchers" toml:"comment-matchers"`
	CommentPrefixes      []string `json:"comment-prefix-identifiers" yaml:"comment-prefix-identifiers" toml:"comment-prefix-identifiers"`
	CommentSuffixes      []string `json:"comment-suffix-identifiers" yaml:"comment-suffix-identifiers" toml:"comment-suffix-identifiers"`
	AutomatedIdentifiers []string `json:"automated-comment-identifiers" yaml:"automated-comment-identifiers" toml:"automated-comment-identifiers"`
	MaxExpression        int      `json:"max-expression-operators" yaml:"max-expression-operators" toml:"max-expression-operators"`
	MaxCondition         int      `json:"max-if-operators" yaml:"max-if-operators" toml:"max-if-operators"`
	MaxDepth             int      `json:"max-control-flow-depth" yaml:"max-control-flow-depth" toml:"max-control-flow-depth"`
	MaxFunction          int      `json:"max-function-lines" yaml:"max-function-lines" toml:"max-function-lines"`
	MinCase              int      `json:"min-case-chain-length" yaml:"min-case-chain-length" toml:"min-case-chain-length"`
	MinDirname           int      `json:"min-dirname-match-depth" yaml:"min-dirname-match-depth" toml:"min-dirname-match-depth"`
	MinLookup            int      `json:"min-object-lookup-chain-length" yaml:"min-object-lookup-chain-length" toml:"min-object-lookup-chain-length"`
}

func DefaultConfig() Config {
	c := Config{MaxExpression: 4, MaxDepth: 3, MaxFunction: 20, MinCase: 3, MinDirname: 3, MinLookup: 3}
	c.Select = []string{"LEG"}
	c.Exclude = []string{".git", ".beads", ".build", "node_modules", "vendor"}
	c.ExecutableEntries = []string{"bin/*.sh", "scripts/*.sh"}
	c.DirectEntries = []string{"bin/*.sh", "scripts/*.sh", "*.sh"}
	c.Runtimes = []string{"bash", "sh", "zsh", "ksh"}
	c.AutomatedIdentifiers = []string{"ai", "chatgpt", "claude", "codex", "copilot", "gemini", "gpt", "llm", "openai"}
	return c
}

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
	s := scanner{path: path, config: config, source: source}
	s.code = bytes.Clone(source)
	s.lines = strings.Split(string(source), "\n")
	s.reported = make(map[string]bool)
	parser := syntax.NewParser(syntax.KeepComments(true), syntax.RecoverErrors(3), syntax.Variant(language(path, source)))
	file, err := parser.Parse(bytes.NewReader(source), path)
	s.prepareCode(file)
	s.checkFiles()
	s.checkComments()
	s.checkLines()
	s.checkStructure(file)
	s.checkTopLevel(file)
	slices.SortStableFunc(s.diagnostics, compareDiagnostics)
	return s.diagnostics, err
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
		if end < start || end > uint(len(s.source)) {
			return false
		}
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
	name := ruleName(code)
	d := Diagnostic{s.path, line, column, code, name, message, trigger, priority}
	s.diagnostics = append(s.diagnostics, d)
}

func (s *scanner) ignored(line int, code string) bool {
	if line < 1 || line > len(s.lines) {
		return false
	}
	raw := s.lines[line-1]
	return strings.Contains(raw, "noqa") && (strings.Contains(raw, code) || strings.Contains(raw, "LEG"))
}

type scope struct {
	depth    int
	loops    int
	function bool
	node     syntax.Node
}

func (s *scanner) checkStructure(file *syntax.File) {
	stack := []scope{{}}
	syntax.Walk(file, func(node syntax.Node) bool {
		if redirect, ok := node.(*syntax.Redirect); ok && redirect.Hdoc != nil {
			return false
		}
		if node == nil {
			stack = stack[:len(stack)-1]
			return true
		}
		parent := stack[len(stack)-1]
		current := s.enterNode(node, parent)
		if current.depth > parent.depth {
			s.checkDepth(node, current.depth)
		}
		current.node = node
		stack = append(stack, current)
		return true
	})
}

func (s *scanner) enterNode(node syntax.Node, parent scope) scope {
	current := parent
	switch n := node.(type) {
	case *syntax.FuncDecl:
		current.function = true
		s.checkFunction(n)
	case *syntax.IfClause:
		s.checkIf(n, parent)
		current.depth += ifDepth(n, parent.node)
	case *syntax.ForClause, *syntax.WhileClause:
		current.depth++
		current.loops++
		s.checkNestedLoop(node, parent.loops)
	case *syntax.CaseClause:
		current.depth++
	default:
		s.checkLeaf(node, parent)
	}
	return current
}

func (s *scanner) checkLeaf(node syntax.Node, parent scope) {
	switch n := node.(type) {
	case *syntax.CallExpr:
		s.checkBooleanArgs(n)
	case *syntax.Assign:
		if parent.function {
			s.checkArgumentBinding(n, parent.node)
		}
	}
}
