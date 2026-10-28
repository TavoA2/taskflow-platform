#!/usr/bin/env bash
# Applies gitops/overlays/local to the local cluster in two phases:
#   1. data tier: namespace, credentials, PostgreSQL, and the migrate Job, which must complete;
#   2. everything else: API, frontend and the HTTPRoute, then wait for their rollouts.
# The API's readiness checks that the database answers, not that the schema exists, so applying the API
# before the migrations finish could serve errors on a first deploy. In Phase 4 ArgoCD sync waves do this.
# Until then this is the only supported way to change what runs in the cluster.
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

echo "deploy: phase 1/2 - data tier and migrations"
# Set-based selector: resources without the component label (namespace, Secret) are included too.
k apply -k "$overlay" -l 'app.kubernetes.io/component notin (api,frontend,routing)'
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

echo "deploy: phase 2/2 - API, frontend and route"
k apply -k "$overlay"
k -n taskflow rollout status deployment/api --timeout=180s
k -n taskflow rollout status deployment/frontend --timeout=180s
k -n taskflow wait httproute/taskflow --for=jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'=True --timeout=60s
k -n taskflow get deploy,statefulset,pod,pvc,job,pdb,httproute -o wide
