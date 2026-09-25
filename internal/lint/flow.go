package lint

import (
	"slices"
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

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
