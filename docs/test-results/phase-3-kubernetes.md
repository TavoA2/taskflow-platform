# Phase 3 - Kubernetes on k3d: test results

- Date: 2026-10-28
- Cluster: k3d `taskflow`, k3s v1.36.5, 1 server + 2 agents, all on one workstation (WSL2, 8 CPUs, 10 GB)
- Images: `taskflow-api` / `taskflow-frontend` at taskflow-app commit `488ce87`, pinned by digest
- Raw output: [phase-3-kubernetes.log](phase-3-kubernetes.log)

Status: **Implemented, Tested**, with one open limitation (latency during the drain of a node that hosts
several critical replicas, see "Open items"). Nothing here demonstrates high availability: every node shares one
host, PostgreSQL is a single replica on node-local storage.

## Exit criteria

| Criterion | Result |
|-----------|--------|
| Cluster, platform and application reproducible from Git alone | **Pass**: deleted and recreated from empty in 426 s, smoke 20/20 |
| Application reachable only through the Gateway, internal endpoints hidden | **Pass**: smoke 20/20, `/metrics` `/readyz` `/healthz` 404 |
| Only digest-pinned images with CI provenance are deployed | **Pass**: `make deploy` and CI fail closed (3 red cases rejected) |
| Probes separate liveness from readiness | **Pass**: DB down -> API NotReady, 0 restarts, recovered in 5 s |
| Data survives pod replacement | **Pass**: task readable after deleting `postgres-0` |
| Rollouts with zero failed requests under load | **Pass**: API 0/4500, frontend 0/4501 |
| Node drain with zero failed requests under load | **Pass for errors** (0/4478, 0/4501); latency criterion **not met** for one node |
| Pod Security `restricted` enforced | **Pass**: root pod rejected; all 5 pods non-root, read-only root, drop ALL, seccomp |

## 1. Image verification (step 3.6)

`make verify-images` renders the overlay and requires every image to be pinned by digest; TaskFlow images must
carry SLSA provenance signed by `TavoA2/taskflow-app/.github/workflows/ci.yml` for `refs/heads/main` on a
GitHub-hosted runner. `make deploy` runs it before applying anything; platform CI runs it on every pull request.

| Case | Expected | Result |
|------|----------|--------|
| Current overlay | 2 attested + PostgreSQL pinned | OK |
| API digest replaced by a digest that does not exist in that repository | reject | FAIL `MANIFEST_UNKNOWN` |
| API image without digest (tag only) | reject | FAIL "not pinned by digest" |
| Signer workflow changed to another file | reject | FAIL (certificate identity mismatch) |
| `make bump-images SHA=c8bd679…` then back to `488ce87…` | overlay updated and verified, then identical | OK, no diff |
| Malformed SHA / unknown SHA | refuse | exit 2 / exit 1 |

## 2. Load and disruption tests

k6 2.3.0 (pinned digest) on the cluster's Docker network, 50 req/s for 90 s, half `GET /`, half
`GET /api/v1/tasks`, disruption 10 s after start (`make disruption-test CASE=...`). Pass = every response 2xx and
no dropped arrivals; p99 < 1 s is reported.

### Final results (after the fixes below, host otherwise idle)

| Case | Failed requests | p99 | max | Dropped | Verdict |
|------|-----------------|-----|-----|---------|---------|
| baseline (no disruption) | 0 / 4501 | 28 ms | 177 ms | 0 | PASS |
| rollout restart API | 0 / 4500 | 18 ms | 705 ms | 0 | PASS |
| rollout restart frontend | 0 / 4501 | 126 ms | 822 ms | 0 | PASS |
| drain agent-1 | 0 / 4501 | 159 ms | 558 ms | 0 | PASS |
| drain agent-0 (proxy, frontend, API, CoreDNS on it) | 0 / 4478 | 1.2 s | 4.06 s | 23 | **FAIL (latency)** |
| baseline on the recreated cluster | 0 / 4501 | 65 ms | 595 ms | 0 | PASS |

### What the tests found, and the fixes

| # | Finding | Evidence | Fix | After |
|---|---------|----------|-----|-------|
| 1 | Frontend rollout returned 503s: nginx exited before Envoy stopped routing to it | 15 failed | `preStop: sleep 5s` on the frontend | 0 failed |
| 1r | Red check: same rollout with the `preStop` removed | 29 / 4502 failed | restored from Git with `make deploy` | 0 failed, smoke 20/20 |
| 2 | Drain of agent-0 evicted the only CoreDNS replica; nginx resolves the API per request | 280 failed, 709 dropped, ~17 s of timeouts | CoreDNS scaled to 2 + PDB (`platform/coredns`) | 0 failed |
| 3 | Envoy proxy was a single replica (one entry point for all traffic) | single pod | `EnvoyProxy`: 2 replicas spread by node + PDB | 2 proxies on 2 nodes |
| 4 | Drain of agent-1 evicted the only Envoy Gateway controller together with a proxy and a frontend: the draining proxy, without a control plane, kept routing to the removed frontend | 245 failed (238 × 503 over 17 s), none from the surviving proxy | controller: 2 replicas (leader election), spread, PDB `minAvailable: 1` | 0 failed |

### Invalid run, kept for the record

A first series ran while another k3d cluster (`devops-lab`) was running on the same host: load average 16-24
on 8 CPUs, CPU idle down to 1 %. Under that pressure the k3s server exited
(`level=fatal msg="Transaction commit failed"`, its embedded SQLite datastore) and restarted; the baseline itself
failed with 502s. The run was discarded and repeated after stopping the other cluster (`k3d cluster stop`,
nothing deleted). Positive side effect: after that control-plane crash the API and PostgreSQL restarted once and
recovered on their own; CoreDNS stayed at 2 replicas (k3s does not revert the scale).

## 3. Functional and failure checks

| Check | Result |
|-------|--------|
| taskflow-app `smoke-test.sh` via `http://127.0.0.1:8088` | 20/20 (before the X-Request-ID policy: 19/20) |
| Delete `postgres-0` | new pod (new UID), same PVC, task created before is returned, API restarts 0 |
| PostgreSQL scaled to 0 (step 3.5) | API pods NotReady, restartCount 0; UI 200, API 502; back to 200 5 s after PostgreSQL Ready |
| Root pod in `taskflow` | Forbidden: violates PodSecurity "restricted:v1.36" |
| securityContext audit (5 pods) | runAsNonRoot, UID 65532/101/70, readOnlyRootFilesystem, no privilege escalation, drop ALL, seccomp RuntimeDefault; 0 ServiceAccount tokens mounted |
| Credentials | `postgres.env` mode 600, matched by `.gitignore`, password absent from tracked files |

## 4. Reproducibility: delete and recreate from Git

| Step | Duration |
|------|----------|
| `make cluster-down` | 28 s (0 containers, 0 volumes left) |
| `make cluster-up` | 59 s |
| `make platform-install` | 183 s (Envoy Gateway, Gateway, EnvoyProxy, CoreDNS scale + PDB) |
| `make local-secrets` | 0 s (existing local file kept) |
| `make deploy` | 154 s (images pulled into fresh nodes; 2 migrate attempts while PostgreSQL started) |
| **Total** | **426 s**, smoke 20/20, 5 PDBs, current kubectl context unchanged |

## Open items

- **Latency during the drain of a node hosting several critical replicas** (proxy, frontend, API, CoreDNS):
  no failed request, but a stall of up to 4 s. Hypotheses: nginx's per-request DNS resolution hitting the
  evicted CoreDNS endpoint before it is removed, or the draining proxy. To be measured with metrics in Phase 6
  and exercised again in Phase 7.
- **Unexplained node container restart**: the `agent-1` container was stopped and started at about 06:19
  (`Sending SIGTERM to k3s`), when the `devops-lab` cluster was started on the same host. Cause not determined.
- PostgreSQL is a single replica on `local-path`: draining the server node interrupts the database. Not tested
  on purpose; an HA database is out of scope (ADR-0007).
- All nodes share one host: these tests prove the application's and the platform's behaviour during voluntary
  disruptions, not infrastructure resilience.
