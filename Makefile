SHELL := /usr/bin/env bash

.PHONY: lint test test-core test-modules

lint:
	bash tools/lint.sh

test: test-core test-modules

test-core:
	bash tests/test-core.sh

test-modules:
	bash tests/test-modules.sh
