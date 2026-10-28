# Phase 0 - Workstation verification

- Date: 2026-10-27
- Result: **PASS**
- Environment: Windows 11 + WSL2 (Ubuntu 26.04, kernel 6.18.33.2-microsoft-standard-WSL2), Docker Desktop (engine 29.6.2)

## 1. `make bootstrap`

Run in both repositories. Both exit 0.

| Check | taskflow-platform | taskflow-app |
|-------|-------------------|--------------|
| git, make, curl, jq, docker | OK | OK |
| kubectl (pinned 1.36.3) | OK 1.36.3 | - |
| k3d (pinned 5.9.0) | OK 5.9.0 | - |
| golang (pinned 1.27.3) | - | OK 1.27.3 |
| Docker engine reachable | OK (29.6.2) | OK (29.6.2) |
| Result | `bootstrap: READY` | `bootstrap: READY` |

## 2. k3d smoke test

```bash
k3d cluster create sandbox --agents 0 --wait --timeout 180s
kubectl --context k3d-sandbox wait --for=condition=Ready node --all --timeout=120s
kubectl --context k3d-sandbox get nodes
kubectl --context k3d-sandbox get pods -A
k3d cluster delete sandbox
```

| Step | Expected | Observed |
|------|----------|----------|
| Create | Cluster created | Created in 28 s |
| Node | 1 node `Ready` | `k3d-sandbox-server-0 Ready control-plane v1.35.5+k3s1` |
| kube-system | Deployments `Running`, Helm install Jobs `Completed` | coredns, local-path-provisioner, metrics-server, traefik, svclb-traefik `Running`; helm-install-traefik(-crd) `Completed` |
| Version skew | kubectl within +/-1 minor of server | client 1.36.3, server 1.35.5: within policy |
| Delete | No leftover containers, volumes or networks | None found |

## Observations

- k3d 5.9.0 defaults to k3s **v1.35.5+k3s1**. Phase 3 pins the k3s image explicitly in the cluster config
  instead of relying on this default.
- `helm-install-traefik` completed after 1 restart: a known startup race while the Traefik CRDs are installed
  by the sibling job; not an error.
- Traefik and ServiceLB are bundled by k3s; whether to keep or disable them is part of the planned Gateway API ADR (Phase 3).
- Other clusters present on the workstation (`k3d devops-lab`, `kind clubscope-dev`) were not modified;
  the previous kubectl context was restored after the test.
