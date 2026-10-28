#!/usr/bin/env bash
# Applies gitops/overlays/local to the local cluster and runs the database migrations to completion.
# Until ArgoCD takes over (Phase 4) this is the only supported way to change what runs in the cluster.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${KUBECTX:?set by the Makefile}"
overlay=gitops/overlays/local
k() { kubectl --context "$KUBECTX" "$@"; }

if [[ ! -f $overlay/secrets/postgres.env ]]; then
  echo "deploy: $overlay/secrets/postgres.env is missing; run 'make local-secrets' first" >&2
  exit 1
fi

# A Job's pod template is immutable, so a new image could not be applied over the previous run.
# Migrations are idempotent: re-running them on an up-to-date schema changes nothing.
k -n taskflow delete job migrate --ignore-not-found --wait=true

k apply -k "$overlay"
k -n taskflow rollout status statefulset/postgres --timeout=180s

pods=(-n taskflow get pods -l batch.kubernetes.io/job-name=migrate)
if ! k -n taskflow wait job/migrate --for=condition=Complete --timeout=300s; then
  echo "deploy: migrate Job did not complete; logs of its latest attempt:" >&2
  k -n taskflow logs "$(k "${pods[@]}" --sort-by=.metadata.creationTimestamp -o name | tail -1)" --tail=50 >&2 || true
  exit 1
fi
# Earlier attempts may have failed while the database was starting (the Job retries them); show the one that succeeded.
echo "deploy: migrate attempts: $(k "${pods[@]}" --no-headers | wc -l)"
k -n taskflow logs "$(k "${pods[@]}" --field-selector=status.phase=Succeeded -o name)"
k -n taskflow get statefulset,pod,pvc,job
