# Contributing

## Development

Install Bash, ShellCheck, and Docker, then run:

```sh
make check
```

The check target runs ShellCheck, direct rule tests, and the linter against its own Bash files.

## Code Style

Keep checks syntax-oriented unless a rule explicitly needs more context. Prefer small helpers, early returns, named intermediate values, and rule functions named after the lint checks they implement.

## Pull Requests

Open focused pull requests with tests for new or changed rules. Include a short before-and-after shell example when changing diagnostics, defaults, or configuration.
