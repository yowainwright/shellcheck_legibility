SHELL := bash
.DEFAULT_GOAL := check
UNIT_TEST := tests/unit/rules.bash
CACHE_TEST := tests/unit/cache.bash
FIXTURE_EXPORT := tests/unit/export-fixtures.bash
export GOCACHE := $(CURDIR)/.build/go-cache
export GOTMPDIR := $(CURDIR)/.build/tmp
E2E_TEST := tests/e2e/docker.bash
E2E_CONTAINER_TEST := tests/e2e/run-in-container.bash
E2E_WRAPPER := tests/e2e/shellcheck-legibility-wrapper
E2E_FILES := $(E2E_TEST) $(E2E_CONTAINER_TEST) $(E2E_WRAPPER)
RELEASE_SCRIPT := scripts/package-release
HOOK_SETUP := scripts/setup/setup.sh
STAGED_LINT := scripts/setup/check-staged.sh
SHELLCHECK_FILES := bin/shellcheck-legibility lib/*.bash $(UNIT_TEST) $(CACHE_TEST) $(FIXTURE_EXPORT) $(E2E_FILES) $(RELEASE_SCRIPT) $(HOOK_SETUP) $(STAGED_LINT)
SELF_LINT_TARGETS := bin lib scripts tests

.PHONY: benchmark build check compatibility e2e install-hooks lint native-test pre-commit self-lint staged-lint test unit

build:
	mkdir -p "$(GOCACHE)" "$(GOTMPDIR)"
	go build -buildvcs=false -trimpath -o .build/shellcheck-legibility .

native-test: build
	go test ./...

check: pre-commit self-lint e2e

benchmark: build
	hyperfine --warmup 1 --runs 5 \
		'bin/shellcheck-legibility check $(SELF_LINT_TARGETS) --no-cache' \
		'bin/shellcheck-legibility check $(SELF_LINT_TARGETS) --cache'

pre-commit: lint native-test unit compatibility staged-lint

compatibility:
	PATH=/usr/bin:/bin /bin/bash $(UNIT_TEST)
	PATH=/usr/bin:/bin SHELLCHECK_LEGIBILITY_ENGINE=bash SKIP_PACKAGE_TEST=1 /bin/bash $(CACHE_TEST)

install-hooks:
	$(HOOK_SETUP)

staged-lint:
	$(STAGED_LINT)

lint:
	test -z "$$(gofmt -l *.go internal)"
	shellcheck -x -S warning $(SHELLCHECK_FILES)
	shfmt -d -i 2 -ci -sr $(SHELLCHECK_FILES)

self-lint:
	bin/shellcheck-legibility check $(SELF_LINT_TARGETS) --no-cache

test: unit e2e

unit: build
	bash $(UNIT_TEST)
	bash $(CACHE_TEST)

e2e:
	bash $(E2E_TEST)
