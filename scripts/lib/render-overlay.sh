# Sourced by scripts that render Kustomize overlays. Overlays read git-ignored secret files
# (secrets/*.env) that do not exist in CI or on a fresh clone; this fills each missing one with its committed
# *.env.example placeholder and removes those copies on exit. Real files are never touched.
# shellcheck shell=bash

placeholders=()
cleanup_placeholders() { rm -f "${placeholders[@]}"; }
trap cleanup_placeholders EXIT

use_placeholder_secrets() {
  local example real
  while IFS= read -r example; do
    real=${example%.example}
    if [[ ! -f $real ]]; then
      cp "$example" "$real"
      placeholders+=("$real")
    fi
  done < <(find gitops -path '*/secrets/*.env.example' 2>/dev/null)
}
