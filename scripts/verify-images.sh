#!/usr/bin/env bash
# Verifies every image an overlay would run, before it reaches the cluster:
#   - every image is pinned by digest (a tag alone can be moved to different content);
#   - every TaskFlow image (ghcr.io/tavoa2/*) has a SLSA provenance attestation signed by taskflow-app's CI
#     workflow, for a build of refs/heads/main on a GitHub-hosted runner (ADR-0005).
# Third-party images (PostgreSQL) are pinned by digest only; nobody here attests them.
# Usage: verify-images.sh [overlay-dir]   (default gitops/overlays/local). Needs gh, authenticated.
set -euo pipefail
cd "$(dirname "$0")/.."

overlay=${1:-gitops/overlays/local}
app_repo=TavoA2/taskflow-app
signer=$app_repo/.github/workflows/ci.yml

# shellcheck source=lib/render-overlay.sh
source scripts/lib/render-overlay.sh
use_placeholder_secrets

mapfile -t images < <(kubectl kustomize "$overlay" | sed -nE 's/^[[:space:]]*image:[[:space:]]*"?([^"[:space:]]+)"?.*/\1/p' | sort -u)
(( ${#images[@]} > 0 )) || { echo "verify-images: no images found in $overlay" >&2; exit 1; }

failed=0
for img in "${images[@]}"; do
  if [[ $img != *@sha256:* ]]; then
    echo "FAIL  $img  (not pinned by digest)"
    failed=1
  elif [[ $img == ghcr.io/tavoa2/* ]]; then
    if out=$(gh attestation verify "oci://$img" --repo "$app_repo" --signer-workflow "$signer" \
        --predicate-type https://slsa.dev/provenance/v1 --source-ref refs/heads/main \
        --deny-self-hosted-runners 2>&1); then
      echo "OK    $img  (SLSA provenance from $signer on refs/heads/main)"
    else
      echo "FAIL  $img  (attestation)"
      sed 's/^/      /' <<<"$out" | tail -5
      failed=1
    fi
  else
    echo "OK    $img  (third-party, pinned by digest, not attested)"
  fi
done
exit "$failed"
