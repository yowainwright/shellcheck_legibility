package lint

import (
	"regexp"
	"slices"
	"strings"
)

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
