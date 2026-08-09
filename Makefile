SHELL := /usr/bin/env bash

.PHONY: lint test test-core test-transaction test-modules

lint:
	bash tools/lint.sh

test: test-core test-transaction test-modules

test-core:
	bash tests/test-core.sh

test-transaction:
	bash tests/test-transaction.sh

test-modules:
	bash tests/test-modules.sh
