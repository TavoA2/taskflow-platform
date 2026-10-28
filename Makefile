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
K6_IMAGE          := grafana/k6:2.3.0@sha256:2dd4756ec6e14e62778916e1eb850108e4b499304c02df56760fa0bdb0fba0b8
export KUBECONFORM_IMAGE KUBE_VERSION KUBECTX K6_IMAGE

# Envoy Gateway (ADR-0006). The chart installs the Gateway API CRDs it was tested with (v1.6.1).
ENVOY_GATEWAY_CHART   := oci://docker.io/envoyproxy/gateway-helm
ENVOY_GATEWAY_VERSION := v1.9.3

.PHONY: help bootstrap secrets-scan validate ruleset ruleset-check cluster-up cluster-down cluster-status platform-install gateway-smoke local-secrets deploy verify-images bump-images disruption-test

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

platform-install: ## Install Envoy Gateway (pinned chart) and the shared Gateway into the local cluster
	helm upgrade --install eg $(ENVOY_GATEWAY_CHART) --version $(ENVOY_GATEWAY_VERSION) \
	  --kube-context $(KUBECTX) --namespace envoy-gateway-system --create-namespace \
	  -f platform/envoy-gateway/values.yaml --wait --timeout 5m
	$(KUBECTL) apply -k platform/gateway
	$(KUBECTL) -n gateway wait gateway/public --for=condition=Programmed --timeout=180s
	$(KUBECTL) -n envoy-gateway-system rollout status deployment -l gateway.envoyproxy.io/owning-gateway-name=public --timeout=180s
	$(KUBECTL) -n gateway get gateway public
	$(KUBECTL) -n kube-system scale deployment/coredns --replicas=2
	$(KUBECTL) apply -k platform/coredns
	$(KUBECTL) -n kube-system rollout status deployment/coredns --timeout=120s

gateway-smoke: ## Route a throwaway backend through the Gateway on 127.0.0.1:8088, then remove it
	./scripts/gateway-smoke.sh

local-secrets: ## Create the git-ignored local database credentials (random password) if missing
	./scripts/local-secrets.sh

deploy: ## Verify images, then apply gitops/overlays/local (data tier and migrations first, then the app)
	./scripts/deploy.sh

verify-images: ## Fail unless every overlay image is digest-pinned and TaskFlow images have CI provenance
	./scripts/verify-images.sh

bump-images: ## Point the local overlay at the images of a taskflow-app commit: make bump-images SHA=<40 chars>
	./scripts/bump-images.sh $(SHA)

disruption-test: ## Steady k6 load while disrupting: make disruption-test CASE="rollout-api|rollout-frontend|drain <node>"
	./scripts/disruption-test.sh $(CASE)
