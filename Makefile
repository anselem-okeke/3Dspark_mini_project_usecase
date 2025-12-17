SHELL := /usr/bin/env bash

.PHONY: up down redeploy kind-up kind-down install uninstall health check deps-ubuntu fix-perms

fix-perms:
	@chmod +x scripts/*.sh || true

up: fix-perms check kind-up install health
	@echo "one-click done (make up)"

down: fix-perms uninstall kind-down
	@echo "removed (make down)"

redeploy: fix-perms check uninstall install health
	@echo "redeployed"

check:
	./scripts/check-deps.sh || ( $(MAKE) deps-ubuntu && ./scripts/check-deps.sh )

deps-ubuntu:
	./scripts/deps-ubuntu.sh

kind-up:
	./scripts/kind-up.sh

kind-down:
	./scripts/kind-down.sh

install:
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

health:
	./scripts/healthcheck.sh
