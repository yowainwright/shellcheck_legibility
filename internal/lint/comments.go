package lint

import (
	"cmp"
	"regexp"
	"slices"
	"strings"
	"unicode"
	"unicode/utf8"

	"mvdan.cc/sh/v3/syntax"
)

func (s *scanner) checkComments() {
	slices.SortFunc(s.comments, func(a, b *syntax.Comment) int { return cmp.Compare(a.Hash.Offset(), b.Hash.Offset()) })
	previous := 0
	for _, comment := range s.comments {
		line, body := int(comment.Hash.Line()), strings.TrimSpace(comment.Text)
		if ignoredComment(body, int(comment.Hash.Col())) {
			continue
		}
		column := utf8.RuneCountInString(s.lines[line-1][:comment.Hash.Col()-1]) + 1
		if line == previous+1 && previous > 0 {
			s.add(line, column, line, 0, "LEG043", "Update or remove the adjacent comment instead of stacking another comment.")
		}
		previous = line
		s.checkAttribution(line, column, body)
		if !s.commentAllowed(body) {
			s.add(line, column, line, 2, "LEG041", "Comment does not match a configured matcher, prefix identifier, or suffix identifier.")
		}
	}
}

func ignoredComment(body string, column int) bool {
	body = strings.ToLower(body)
	return (column == 1 && strings.HasPrefix(body, "!")) || strings.HasPrefix(body, "shellcheck") || strings.HasPrefix(body, "noqa")
}

func (s *scanner) commentAllowed(body string) bool {
	body = strings.ToLower(body)
	for _, matcher := range s.config.CommentMatchers {
		if matchesComment(body, matcher) {
			return true
		}
	}
	for _, prefix := range s.config.CommentPrefixes {
		if identifierMatch(body, prefix, false) {
			return true
		}
	}
	for _, suffix := range s.config.CommentSuffixes {
		if identifierMatch(body, suffix, true) {
			return true
		}
	}
	return false
}

func matchesComment(body, matcher string) bool {
	pattern := strings.ToLower(strings.TrimSpace(matcher))
	if pattern == "" {
		return false
	}
	matched, err := regexp.MatchString(pattern, body)
	return err == nil && matched
}

func identifierMatch(body, identifier string, suffix bool) bool {
	identifier = strings.ToLower(strings.TrimSpace(identifier))
	if identifier == "" {
		return false
	}
	if suffix {
		if !strings.HasSuffix(body, identifier) {
			return false
		}
		prefix := strings.TrimSuffix(body, identifier)
		return prefix == "" || !wordCharacter(rune(prefix[len(prefix)-1]))
	}
	if !strings.HasPrefix(body, identifier) {
		return false
	}
	if !wordCharacter(rune(identifier[len(identifier)-1])) {
		return true
	}
	rest := strings.TrimPrefix(body, identifier)
	return rest == "" || !wordCharacter(rune(rest[0]))
}

func wordCharacter(char rune) bool {
	return char >= 'a' && char <= 'z' || char >= 'A' && char <= 'Z' || char >= '0' && char <= '9' || char == '_'
}

func normalizeAttribution(value string) string {
	value = strings.Map(func(char rune) rune {
		if unicode.IsLetter(char) || unicode.IsDigit(char) {
			return unicode.ToLower(char)
		}
		return ' '
	}, value)
	return strings.Join(strings.Fields(value), " ")
}

var authorSignature = regexp.MustCompile(`(^|[[:space:]])@author([[:space:]]|:)+(.+)$`)

func (s *scanner) checkAttribution(line, column int, body string) {
	if !s.config.Enabled("LEG042") {
		return
	}
	lower, normalized := strings.ToLower(body), normalizeAttribution(body)
	author := ""
	if match := authorSignature.FindStringSubmatch(lower); match != nil {
		author = normalizeAttribution(match[3])
	}
	for _, identifier := range s.config.AutomatedIdentifiers {
		if !attributesTo(lower, normalized, author, identifier) {
			continue
		}
		message := "Comment contains the prohibited attribution \"" + identifier + "\"."
		s.add(line, column, line, 1, "LEG042", message)
		return
	}
}

func attributesTo(body, normalized, author, identifier string) bool {
	name := normalizeAttribution(identifier)
	if name == "" {
		return false
	}
	if phrasePresent(author, name) {
		return true
	}
	for _, verb := range []string{"authored", "created", "generated", "produced", "written"} {
		if phrasePresent(normalized, name+" "+verb) {
			return true
		}
		for _, article := range []string{"", "a ", "an "} {
			phrase := verb + " by " + article + strings.ToLower(identifier)
			if passiveSignature(body, phrase) {
				return true
			}
		}
	}
	return false
}

func phrasePresent(body, phrase string) bool {
	return strings.Contains(" "+body+" ", " "+phrase+" ")
}

func passiveSignature(body, phrase string) bool {
	for {
		prefix, suffix, found := strings.Cut(body, phrase)
		if !found {
			return false
		}
		leftBoundary := prefix == "" || !wordCharacter(rune(prefix[len(prefix)-1]))
		if leftBoundary && attributionBoundary(suffix) {
			return true
		}
		body = suffix
	}
}

func attributionBoundary(suffix string) bool {
	trimmed := strings.TrimSpace(suffix)
	if trimmed == "" || strings.ContainsRune(".,;:!?)]}", rune(trimmed[0])) {
		return true
	}
	conjunctions := []string{"and", "but", "for", "nor", "or", "so", "yet"}
	return suffix != strings.TrimLeft(suffix, " \t\r\n") && slices.Contains(conjunctions, firstWord(trimmed))
}
