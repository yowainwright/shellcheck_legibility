package lint

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
