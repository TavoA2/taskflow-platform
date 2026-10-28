#!/usr/bin/env bash
# Keeps a steady load on the application through the Gateway (k6) while a disruption happens, and fails if any
# request did not get a 2xx. k6 runs in a pinned container on the cluster's Docker network.
# Usage: disruption-test.sh baseline | rollout-api | rollout-frontend | drain <node>
# "baseline" applies the same load with no disruption: the control to compare the other cases against.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${KUBECTX:?set by the Makefile}"
K6_IMAGE=${K6_IMAGE:?set by the Makefile}
k() { kubectl --context "$KUBECTX" "$@"; }

case=${1:-}
case $case in
  baseline | rollout-api | rollout-frontend) ;;
  drain) node=${2:?usage: $0 drain <node>} ;;
  *) echo "usage: $0 baseline | rollout-api | rollout-frontend | drain <node>" >&2; exit 2 ;;
esac

disrupt() {
  sleep 10 # steady state first
  case $case in
    baseline)         : ;;
    rollout-api)    k -n taskflow rollout restart deployment/api && k -n taskflow rollout status deployment/api --timeout=180s ;;
    rollout-frontend) k -n taskflow rollout restart deployment/frontend && k -n taskflow rollout status deployment/frontend --timeout=180s ;;
    drain)
      # Evictions honour PodDisruptionBudgets; the node is made schedulable again afterwards.
      k drain "$node" --ignore-daemonsets --delete-emptydir-data --timeout=180s
      k -n taskflow rollout status deployment/api --timeout=180s
      k -n taskflow rollout status deployment/frontend --timeout=180s
      k uncordon "$node" ;;
  esac
  echo "disruption-test: $case finished at $(date -u +%T)"
}

echo "disruption-test: $case, load ${RATE:-50} req/s for ${DURATION:-90s}, started at $(date -u +%T)"
disrupt &
disrupt_pid=$!
rc=0
docker run --rm -i --network k3d-taskflow -e RATE="${RATE:-50}" -e DURATION="${DURATION:-90s}" \
  "$K6_IMAGE" run --quiet - <tests/k6/steady-load.js || rc=$?
wait "$disrupt_pid" || { echo "disruption-test: the disruption itself failed" >&2; rc=1; }
[[ $case == drain ]] && k uncordon "$node" >/dev/null 2>&1 || true
echo "disruption-test: $case $([[ $rc == 0 ]] && echo PASS || echo FAIL)"
exit "$rc"
