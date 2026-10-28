#!/usr/bin/env bash
# Points the local overlay at the images taskflow-app CI published for one commit: looks up each image's
# digest in GHCR by its commit-SHA tag, rewrites newTag and digest, then verifies the result.
# Usage: bump-images.sh <full 40-character commit SHA of taskflow-app>
# In Phase 4 the same change arrives as an automated pull request instead.
set -euo pipefail
cd "$(dirname "$0")/.."

sha=${1:-}
[[ $sha =~ ^[0-9a-f]{40}$ ]] || { echo "usage: $0 <40-character commit SHA>" >&2; exit 2; }
file=gitops/overlays/local/kustomization.yaml

for component in api frontend; do
  digest=$(gh api "/users/TavoA2/packages/container/taskflow-$component/versions?per_page=100" \
    -q ".[] | select(.metadata.container.tags | index(\"$sha\")) | .name")
  [[ $digest == sha256:* ]] || { echo "bump-images: taskflow-$component:$sha not found in GHCR" >&2; exit 1; }
  # Rewrite the newTag/digest lines of this image's entry only (the entry starts at "- name: taskflow-<component>").
  awk -v name="taskflow-$component" -v tag="$sha" -v dig="$digest" '
    /^  - name: / { inside = ($3 == name) }
    inside && /^    newTag: / { $0 = "    newTag: " tag }
    inside && /^    digest: / { $0 = "    digest: " dig }
    { print }' "$file" >"$file.tmp" && mv "$file.tmp" "$file"
  echo "bump-images: taskflow-$component -> ${sha:0:7} $digest"
done

./scripts/verify-images.sh
git --no-pager diff --stat -- "$file"
