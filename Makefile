SHELL := /usr/bin/env bash

.PHONY: up down redeploy kind-up kind-down install uninstall health check deps-ubuntu fix-perms

fix-perms:
	@chmod +x scripts/*.sh 2>/dev/null || true

check: fix-perms
	@./scripts/check-deps.sh || ( $(MAKE) deps-ubuntu && ./scripts/check-deps.sh )

deps-ubuntu: fix-perms
	@./scripts/deps-ubuntu.sh

up: check kind-up install health
	@echo "one-click done (make up)"

down: fix-perms uninstall kind-down
	@echo "removed (make down)"

redeploy: fix-perms uninstall install health
	@echo "redeployed"

kind-up: fix-perms
	@./scripts/kind-up.sh

kind-down: fix-perms
	@./scripts/kind-down.sh

install: fix-perms
	@./scripts/install.sh

uninstall: fix-perms
	@./scripts/uninstall.sh

health: fix-perms
	@./scripts/healthcheck.sh

