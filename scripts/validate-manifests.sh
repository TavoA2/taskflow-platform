#!/usr/bin/env bash
# Renders every Kustomize directory under gitops/ and platform/ and validates the output against the
# Kubernetes JSON schema (KUBE_VERSION) with kubeconform, in strict mode (unknown fields are errors).
# Custom resources (Gateway API, Envoy Gateway...) are validated against the community CRD catalog;
# kinds with no published schema fail instead of being skipped silently.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${KUBECONFORM_IMAGE:?set by the Makefile}" "${KUBE_VERSION:?set by the Makefile}"

mapfile -t dirs < <(find gitops platform -name kustomization.yaml -printf '%h\n' 2>/dev/null | sort)
if (( ${#dirs[@]} == 0 )); then
  echo "validate-manifests: no Kustomize directories yet (gitops/, platform/)"
  exit 0
fi

failed=0
for dir in "${dirs[@]}"; do
  echo "--- $dir"
  if ! kubectl kustomize "$dir" | docker run --rm -i "$KUBECONFORM_IMAGE" \
      -strict -summary -kubernetes-version "$KUBE_VERSION" \
      -schema-location default \
      -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
      -; then
    failed=1
  fi
done
exit "$failed"
