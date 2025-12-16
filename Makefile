SHELL := /usr/bin/env bash

.PHONY: up down redeploy kind-up kind-down install uninstall health

up: kind-up install health
	@echo "one-click done (make up)"

down: uninstall kind-down
	@echo "removed (make down)"

redeploy: uninstall install health
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
