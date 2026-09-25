package lint

import (
	"fmt"
	"slices"
	"strings"
)

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
