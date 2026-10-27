SHELL := /bin/bash
.DEFAULT_GOAL := help

GITLEAKS_IMAGE := ghcr.io/gitleaks/gitleaks:v8.30.1

.PHONY: help bootstrap secrets-scan

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Verify workstation tools against .tool-versions (read-only)
	@./scripts/bootstrap.sh

secrets-scan: ## Scan the full git history for secrets with gitleaks (read-only mount)
	docker run --rm -u $$(id -u):$$(id -g) -v "$(CURDIR)":/repo:ro $(GITLEAKS_IMAGE) git /repo --redact --no-banner
