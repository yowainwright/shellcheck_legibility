SHELL := bash
.DEFAULT_GOAL := check
UNIT_TEST := internal/bash/rules_test.bash
CACHE_TEST := tests/integration/cache.bash
export GOCACHE := $(CURDIR)/.build/go-cache
export GOTMPDIR := $(CURDIR)/.build/tmp
E2E_TEST := tests/e2e/docker.bash
E2E_CONTAINER_TEST := tests/e2e/run-in-container.bash
E2E_FILES := $(E2E_TEST) $(E2E_CONTAINER_TEST)
RELEASE_SCRIPT := scripts/package-release
HOOK_SETUP := scripts/setup/setup.sh
STAGED_LINT := scripts/setup/check-staged.sh
SHELLCHECK_FILES := internal/bash/*.bash tests/integration/*.bash $(E2E_FILES) $(RELEASE_SCRIPT) $(HOOK_SETUP) $(STAGED_LINT)
SELF_LINT_TARGETS := internal scripts tests

.PHONY: benchmark build check compatibility e2e install-hooks integration lint pre-commit self-lint staged-lint test unit

build:
	mkdir -p bin "$(GOCACHE)" "$(GOTMPDIR)"
	go build -buildvcs=false -trimpath -o bin/shellcheck-legibility ./cmd/shellcheck-legibility

check: pre-commit self-lint e2e

benchmark: build
	hyperfine --warmup 1 --runs 5 \
		'bin/shellcheck-legibility check $(SELF_LINT_TARGETS) --no-cache' \
		'bin/shellcheck-legibility check $(SELF_LINT_TARGETS) --cache'

pre-commit: lint unit compatibility integration staged-lint

compatibility: build
	PATH=/usr/bin:/bin /bin/bash $(UNIT_TEST)
	PATH=/usr/bin:/bin SHELLCHECK_LEGIBILITY_ENGINE=bash SKIP_PACKAGE_TEST=1 /bin/bash $(CACHE_TEST)

install-hooks:
	$(HOOK_SETUP)

staged-lint: build
	$(STAGED_LINT)

lint:
	test -z "$$(gofmt -l cmd internal tests/integration)"
	shellcheck -x -S warning $(SHELLCHECK_FILES)
	shfmt -d -i 2 -ci -sr $(SHELLCHECK_FILES)

self-lint: build
	bin/shellcheck-legibility check $(SELF_LINT_TARGETS) --no-cache

test: unit integration e2e

unit: build
	go test ./cmd/... ./internal/...
	bash $(UNIT_TEST)

integration: build
	go test ./tests/integration
	bash $(CACHE_TEST)
	bash tests/integration/staged.bash

e2e:
	bash $(E2E_TEST)
