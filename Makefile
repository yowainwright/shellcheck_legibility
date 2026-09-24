SHELL := bash
UNIT_TEST := tests/unit/rules.bash
E2E_TEST := tests/e2e/docker.bash
E2E_CONTAINER_TEST := tests/e2e/run-in-container.bash
E2E_WRAPPER := tests/e2e/shellcheck-legibility-wrapper
E2E_FILES := $(E2E_TEST) $(E2E_CONTAINER_TEST) $(E2E_WRAPPER)
RELEASE_SCRIPT := scripts/package-release
HOOK_SETUP := scripts/setup/setup.sh
STAGED_LINT := scripts/setup/check-staged.sh
SHELLCHECK_FILES := bin/shellcheck-legibility lib/*.bash $(UNIT_TEST) $(E2E_FILES) $(RELEASE_SCRIPT) $(HOOK_SETUP) $(STAGED_LINT)
SELF_LINT_TARGETS := bin lib scripts tests

.PHONY: check compatibility e2e install-hooks lint pre-commit self-lint staged-lint test unit

check: pre-commit self-lint e2e

pre-commit: lint unit compatibility staged-lint

compatibility:
	PATH=/usr/bin:/bin /bin/bash $(UNIT_TEST)

install-hooks:
	$(HOOK_SETUP)

staged-lint:
	$(STAGED_LINT)

lint:
	shellcheck -x -S warning $(SHELLCHECK_FILES)
	shfmt -d -i 2 -ci -sr $(SHELLCHECK_FILES)

self-lint:
	bin/shellcheck-legibility check $(SELF_LINT_TARGETS)

test: unit e2e

unit:
	bash $(UNIT_TEST)

e2e:
	bash $(E2E_TEST)
