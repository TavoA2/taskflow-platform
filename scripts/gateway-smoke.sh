#!/usr/bin/env bash
# End-to-end Gateway test: deploy a throwaway backend, reach it through 127.0.0.1:8088 via an HTTPRoute,
# then remove it. Exit code 0 only if the request routed through the Gateway returned the backend's page.
set -euo pipefail
cd "$(dirname "$0")/.."
ctx=${KUBECTX:?set by the Makefile}
url=${GATEWAY_URL:-http://127.0.0.1:8088}/gateway-smoke/
k() { kubectl --context "$ctx" "$@"; }
cleanup() { k delete -k platform/gateway-smoke --ignore-not-found --wait=false >/dev/null; }
trap cleanup EXIT

k apply -k platform/gateway-smoke >/dev/null
k -n gateway-smoke rollout status deploy/echo --timeout=120s >/dev/null
k -n gateway-smoke wait httproute/echo --for=jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'=True --timeout=60s >/dev/null

for _ in $(seq 1 30); do
  if curl -fsS --max-time 3 "$url" | grep -q 'Welcome to nginx'; then
    echo "gateway-smoke: PASS ($url routed through the Gateway to the backend)"
    exit 0
  fi
  sleep 2
done
echo "gateway-smoke: FAIL ($url did not return the backend page)" >&2
exit 1
