package lint

import (
	"fmt"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"unicode"

	"mvdan.cc/sh/v3/pattern"
	"mvdan.cc/sh/v3/syntax"
)

func ifDepth(node *syntax.IfClause, parent syntax.Node) int {
	if clause, ok := parent.(*syntax.IfClause); ok && clause.Else == node {
		return 0
	}
	return 1
}

func (s *scanner) checkDepth(node syntax.Node, depth int) {
	if depth <= s.config.MaxDepth {
		return
	}
	line := int(node.Pos().Line())
	message := fmt.Sprintf("Control-flow depth is %d (max %d). Prefer guard clauses or extracted functions.", depth, s.config.MaxDepth)
	s.add(line, 1, line, 80, "LEG003", message)
}

func (s *scanner) checkNestedLoop(node syntax.Node, enclosing int) {
	if enclosing == 0 {
		return
	}
	line := int(node.Pos().Line())
	s.add(line, 1, line, 75, "LEG005", "Nested loop detected. Consider a lookup, case statement, or extracted function.")
}

func (s *scanner) checkFunction(function *syntax.FuncDecl) {
	start, end := int(function.Pos().Line()), int(function.End().Line())
	lines := end - start + 1
	if lines > s.config.MaxFunction {
		message := fmt.Sprintf("Function has %d lines (max %d). Extract focused helper functions.", lines, s.config.MaxFunction)
		s.add(start, 1, end, 5, "LEG038", message)
	}
	body, ok := function.Body.Cmd.(*syntax.Block)
	if !ok || len(body.Stmts) != 1 || start == end {
		return
	}
	conditional, ok := body.Stmts[0].Cmd.(*syntax.IfClause)
	if !ok || conditional.Else != nil || exits(conditional.Then, false) {
		return
	}
	line := int(conditional.Pos().Line())
	s.add(line, 1, end, 4, "LEG010", "Prefer a guard clause before the main path instead of wrapping function logic in an if block.")
}

func (s *scanner) checkIf(conditional *syntax.IfClause, parent scope) {
	if _, alternative := parent.node.(*syntax.IfClause); alternative {
		return
	}
	if conditional.Else == nil {
		return
	}
	s.checkIfChain(conditional)
	if len(conditional.Else.Cond) != 0 || !exits(conditional.Then, parent.loops > 0) {
		return
	}
	line := int(conditional.Else.Pos().Line())
	s.add(line, 1, line, 70, "LEG009", "Avoid else after a branch exits. Return or continue early and keep the follow-up path unindented.")
}

func (s *scanner) checkIfChain(conditional *syntax.IfClause) {
	name := comparisonName(strings.TrimSpace(s.lines[conditional.Pos().Line()-1]))
	if name == "" {
		return
	}
	count := 1
	for next := conditional.Else; next != nil; next = next.Else {
		line := int(next.Pos().Line())
		if comparisonName(strings.TrimSpace(s.lines[line-1])) != name {
			continue
		}
		count++
		if count < s.config.MinCase {
			continue
		}
		message := fmt.Sprintf("If chain compares %s %d times. Prefer a case statement.", name, count)
		s.add(line, 1, line, 80, "LEG034", message)
		return
	}
}

func (s *scanner) checkBooleanArgs(call *syntax.CallExpr) {
	expectingCommand := true
	for _, arg := range call.Args {
		literal := arg.Lit()
		if expectingCommand {
			expectingCommand = commandPrefix(literal)
			continue
		}
		if literal != "true" && literal != "false" {
			continue
		}
		line := int(arg.Pos().Line())
		s.add(line, 1, line, 40, "LEG035", "Avoid boolean literal arguments. Name the option before passing it.")
	}
}

func commandPrefix(word string) bool {
	prefixes := []string{"!", "command", "builtin", "exec", "env", "time"}
	return slices.Contains(prefixes, word) || strings.HasPrefix(word, "-") || strings.Contains(word, "=")
}

func (s *scanner) checkTopLevel(file *syntax.File) {
	names := map[string]bool{"main": true}
	for _, stmt := range file.Stmts {
		if function, ok := stmt.Cmd.(*syntax.FuncDecl); ok {
			names[function.Name.Value] = true
			continue
		}
		if topLevelAllowed(stmt, names) {
			continue
		}
		line := int(stmt.Pos().Line())
		s.add(line, 1, line, 50, "LEG039", "Move top-level script logic into named functions and keep only setup plus function dispatch at the top level.")
		return
	}
}

func topLevelAllowed(stmt *syntax.Stmt, names map[string]bool) bool {
	if _, ok := stmt.Cmd.(*syntax.DeclClause); ok {
		return true
	}
	call, ok := stmt.Cmd.(*syntax.CallExpr)
	if !ok {
		return false
	}
	if len(call.Args) == 0 {
		return len(call.Assigns) > 0
	}
	command := call.Args[0].Lit()
	setup := []string{"set", "shopt", "trap", "source", ".", "export", "readonly", "declare", "typeset"}
	return names[command] || slices.Contains(setup, command)
}

func (s *scanner) checkLines() {
	for index, code := range strings.Split(string(s.code), "\n") {
		if strings.TrimSpace(code) == "" {
			continue
		}
		raw := strings.TrimSpace(s.lines[index])
		s.checkExpression(index+1, raw, code)
		s.checkCondition(index+1, raw, code)
		s.checkLookup(index+1, raw)
		s.checkSmoke(index+1, raw)
	}
}

func (s *scanner) checkExpression(line int, raw, code string) {
	controls := []string{"if", "elif", "while", "until", "for", "case", "else", "fi", "done", "esac"}
	if slices.Contains(controls, firstWord(raw)) {
		return
	}
	pipes := strings.NewReplacer("||", "", "|&", "").Replace(code)
	count := strings.Count(code, "&&") + strings.Count(code, "||") + strings.Count(pipes, "|")
	if count <= s.config.MaxExpression {
		return
	}
	message := fmt.Sprintf("Expression has %d legibility operators (max %d). Extract named commands or values.", count, s.config.MaxExpression)
	s.add(line, 1, line, 10, "LEG001", message)
}

func (s *scanner) checkCondition(line int, raw, code string) {
	if !slices.Contains([]string{"if", "elif", "while", "until"}, firstWord(raw)) {
		return
	}
	condition := " " + conditionText(strings.TrimSpace(code)) + " "
	count := 0
	for _, operator := range []string{"&&", "||", " -a ", " -o ", " ! "} {
		count += strings.Count(condition, operator)
	}
	if count <= s.config.MaxCondition {
		return
	}
	message := fmt.Sprintf("Condition has %d legibility operators (max %d). Hoist it into a named check.", count, s.config.MaxCondition)
	s.add(line, 1, line, 70, "LEG002", message)
}

func conditionText(line string) string {
	for _, word := range []string{"if ", "elif ", "while ", "until "} {
		line = strings.TrimPrefix(line, word)
	}
	line, _, _ = strings.Cut(line, "; then")
	line, _, _ = strings.Cut(line, "; do")
	return line
}

func comparisonName(line string) string {
	words := strings.Fields(conditionText(line))
	if len(words) < 3 || !slices.Contains([]string{"[[", "[", "test"}, words[0]) {
		return ""
	}
	operators := []string{"==", "=", "-eq", "-ne", "-lt", "-le", "-gt", "-ge"}
	if !slices.Contains(operators, words[2]) {
		return ""
	}
	return words[1]
}

func (s *scanner) checkLookup(line int, raw string) {
	name := comparisonName(raw)
	if name == "" || strings.Count(raw, name) < s.config.MinLookup {
		return
	}
	s.add(line, 1, line, 20, "LEG024", "Replace repeated "+name+" equality checks with a case statement or lookup.")
}

func (s *scanner) checkSmoke(line int, raw string) {
	words := strings.Fields(raw)
	if len(words) < 2 || !runtimeAllowed(words[0], s.config.Runtimes) {
		return
	}
	for _, word := range words[1:] {
		if strings.HasPrefix(word, "-") || !matchesAny(word, s.config.DirectEntries) {
			continue
		}
		message := fmt.Sprintf("Smoke tests should execute the installed command, not `%s %s`, so packaging and shebangs are exercised.", words[0], word)
		s.add(line, 1, line, 30, "LEG017", message)
		return
	}
}

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

type outcomes struct{ success, failure bool }

func exits(statements []*syntax.Stmt, loop bool) bool {
	for _, stmt := range statements {
		flow := statementOutcomes(stmt, loop)
		if !flow.success && !flow.failure {
			return true
		}
	}
	return false
}

func statementOutcomes(stmt *syntax.Stmt, loop bool) outcomes {
	if stmt.Background {
		return outcomes{true, true}
	}
	switch command := stmt.Cmd.(type) {
	case *syntax.CallExpr:
		if exitCall(command, loop) {
			return outcomes{}
		}
	case *syntax.BinaryCmd:
		return binaryOutcomes(command, loop)
	case *syntax.Block:
		if exits(command.Stmts, loop) {
			return outcomes{}
		}
	}
	return outcomes{true, true}
}

func exitCall(call *syntax.CallExpr, loop bool) bool {
	prefixes := []string{"command", "builtin", "exec", "time", "!"}
	for _, arg := range call.Args {
		word := arg.Lit()
		if slices.Contains(prefixes, word) || strings.HasPrefix(word, "-") {
			continue
		}
		return word == "return" || word == "exit" || (loop && (word == "break" || word == "continue"))
	}
	return false
}

func binaryOutcomes(command *syntax.BinaryCmd, loop bool) outcomes {
	left, right := statementOutcomes(command.X, loop), statementOutcomes(command.Y, loop)
	switch command.Op {
	case syntax.AndStmt:
		return outcomes{left.success && right.success, left.failure || (left.success && right.failure)}
	case syntax.OrStmt:
		return outcomes{left.success || (left.failure && right.success), left.failure && right.failure}
	}
	return outcomes{true, true}
}

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
