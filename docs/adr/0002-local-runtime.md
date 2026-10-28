# ADR-0002: k3d as the local Kubernetes runtime

- Status: Accepted
- Date: 2026-10-27

## Context

Phases 3-7 need a local Kubernetes cluster that is cheap to create and destroy, reproducible from code,
able to run several nodes, and light enough for the workstation: Windows 11 + WSL2 + Docker Desktop,
16 GB of host RAM with about 7.6 GiB available to WSL2 by default. Later phases add ArgoCD and
kube-prometheus-stack, which are memory-hungry, so baseline overhead matters.

Target path: local k3d -> (optional) k3s on EC2 provisioned by Terraform -> EKS only in Phase 9 as ephemeral sessions.

## Decision

Use **k3d** (k3s nodes running as Docker containers) as the local runtime. The cluster definition will be
a versioned k3d config file in this repository (Phase 3), never ad-hoc CLI flags, so it can be recreated
identically. The k3s image is pinned explicitly in that config.

## Alternatives considered

| Option | Why not chosen |
|--------|----------------|
| kind | Upstream kubeadm-based and closest to "vanilla" Kubernetes, but heavier per node on this machine; no bundled load balancer or storage. |
| minikube | Mature, but the multi-node and driver story on WSL2 is less smooth; heavier VM-based defaults. |
| Docker Desktop Kubernetes | Zero setup, but single node, version tied to Docker Desktop, cannot be defined or recreated from Git. |
| k3s directly in WSL2 | Lightest, but needs systemd in WSL and mutates the host; harder to destroy cleanly. |

## Consequences

- Positive: fast create/delete (seconds), multi-node via agents, built-in load balancer and local registry
  support; the same distribution (k3s) can later run on EC2, keeping the `local` and `ec2` overlays close.
- Negative / limitations (documented, not hidden):
  - k3s bundles components that EKS does not (Traefik, ServiceLB, local-path provisioner, embedded SQLite/etcd).
    Which bundled components are disabled is decided in Phase 3 (see the planned Gateway API ADR).
  - `local-path` volumes live on one node's disk: data survives pod restarts but not node loss. This is
    **not** highly available storage, and no HA claim is made from local tests.
  - All nodes share one host; failure tests (Phase 7) prove application behaviour, not infrastructure resilience.
  - Differences from EKS (IAM, ALB, EBS CSI, VPC CNI) are handled only in the `aws` overlay.

## Verification

Smoke test, expected to pass before Phase 3 starts:

```bash
k3d cluster create sandbox --agents 0
kubectl get nodes          # 1 node, STATUS Ready
kubectl get pods -A        # kube-system pods Running/Completed
k3d cluster delete sandbox
```
