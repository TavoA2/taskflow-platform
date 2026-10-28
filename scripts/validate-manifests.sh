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

# Overlays read git-ignored secret files (secrets/*.env) that do not exist in CI. Render them with the
# committed *.env.example placeholders instead; files created here are removed on exit, real ones are untouched.
placeholders=()
trap 'rm -f "${placeholders[@]}"' EXIT
while IFS= read -r example; do
  real=${example%.example}
  if [[ ! -f $real ]]; then
    cp "$example" "$real"
    placeholders+=("$real")
  fi
done < <(find gitops -path '*/secrets/*.env.example' 2>/dev/null)

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
