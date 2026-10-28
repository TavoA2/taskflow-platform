SHELL := /bin/bash
.DEFAULT_GOAL := help

GITHUB_REPO := TavoA2/taskflow-platform

# Local cluster. Every kubectl call names the context explicitly: the user's current context is never used,
# so nothing here can be applied to another cluster by accident.
CLUSTER := taskflow
KUBECTX := k3d-$(CLUSTER)
KUBECTL := kubectl --context $(KUBECTX)

# Tools run from pinned container images, so local runs and CI use exactly the same versions.
GITLEAKS_IMAGE    := ghcr.io/gitleaks/gitleaks:v8.30.1
ACTIONLINT_IMAGE  := rhysd/actionlint:1.7.12
KUBECONFORM_IMAGE := ghcr.io/yannh/kubeconform:v0.8.0
KUBE_VERSION      := 1.36.0
export KUBECONFORM_IMAGE KUBE_VERSION

.PHONY: help bootstrap secrets-scan validate ruleset ruleset-check cluster-up cluster-down cluster-status

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Verify workstation tools against .tool-versions (read-only)
	@./scripts/bootstrap.sh

secrets-scan: ## Scan the full git history for secrets with gitleaks (read-only mount)
	docker run --rm -u $$(id -u):$$(id -g) -v "$(CURDIR)":/repo:ro $(GITLEAKS_IMAGE) git /repo --redact --no-banner

validate: ## Lint workflows and validate every Kustomize build against the Kubernetes schema
	docker run --rm -v "$(CURDIR)":/src:ro -w /src $(ACTIONLINT_IMAGE) -no-color
	./scripts/validate-manifests.sh

ruleset: ## Create or update the main-branch ruleset on GitHub from .github/rulesets/main.json (admin)
	./scripts/apply-ruleset.sh $(GITHUB_REPO) .github/rulesets/main.json

ruleset-check: ## Fail if the live ruleset on GitHub differs from .github/rulesets/main.json
	./scripts/apply-ruleset.sh $(GITHUB_REPO) .github/rulesets/main.json --check

cluster-up: ## Create (or start) the local k3d cluster defined in k3d/taskflow-local.yaml
	@if k3d cluster list $(CLUSTER) >/dev/null 2>&1; then \
	  echo "cluster $(CLUSTER) already exists, starting it"; k3d cluster start $(CLUSTER); \
	else k3d cluster create --config k3d/taskflow-local.yaml; fi
	$(KUBECTL) wait --for=condition=Ready node --all --timeout=180s
	$(KUBECTL) get nodes -o wide

cluster-down: ## Delete the local k3d cluster with its volumes (all data in it is lost)
	k3d cluster delete $(CLUSTER)

cluster-status: ## Nodes and system pods of the local cluster
	$(KUBECTL) get nodes -o wide
	$(KUBECTL) get pods -A -o wide
