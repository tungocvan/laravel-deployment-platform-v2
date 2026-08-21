SHELL := /usr/bin/env bash

.PHONY: lint test test-core test-transaction test-audit test-package test-lifecycle test-modules test-site test-ui

lint:
	bash tools/lint.sh

test: test-core test-transaction test-audit test-package test-lifecycle test-modules test-site test-ui

test-core:
	bash tests/test-core.sh

test-transaction:
	bash tests/test-transaction.sh

test-audit:
	bash tests/test-audit.sh

test-package:
	bash modules/package/tests/test-package.sh

test-lifecycle:
	bash modules/lifecycle/tests/test-lifecycle.sh

test-modules:
	bash tests/test-modules.sh

test-site:
	bash modules/site/tests/test-site.sh

test-ui:
	bash modules/ui/tests/test-ui.sh
