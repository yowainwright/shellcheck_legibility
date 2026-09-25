package lint

import (
	"fmt"
	"slices"
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

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
