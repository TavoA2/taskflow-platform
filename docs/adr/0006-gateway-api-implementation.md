# ADR-0006: Gateway API with Envoy Gateway for the local cluster

- Status: Accepted
- Date: 2026-10-28

## Context

TaskFlow needs one public HTTP entry point per environment. ingress-nginx has been retired upstream, and the
Kubernetes project's successor API for north-south traffic is **Gateway API** (`GatewayClass`, `Gateway`,
`HTTPRoute`), which separates who runs the entry point (platform) from who routes to it (applications).
The same routing definitions should work locally (k3d), on EC2 (k3s) and on EKS, changing only the
implementation behind them. The local cluster runs k3s v1.36, which bundles Traefik.

## Decision

- Use **Gateway API v1** resources for all external routing; no `Ingress` objects.
- Locally, implement it with **Envoy Gateway v1.9.3**, installed from its pinned Helm chart
  (`make platform-install`), which also installs the Gateway API CRDs it is tested with (**v1.6.1**).
  k3s's bundled Traefik is disabled (`--disable=traefik`); k3s ServiceLB exposes the Envoy proxy Service.
- One **shared `Gateway`** (`gateway/public`) owned by the platform; applications attach `HTTPRoute`s only
  from namespaces labelled `gateway-access: "true"` (`allowedRoutes` selector).
- Environment differences live only in the overlays: the `GatewayClass` (Envoy Gateway locally, the AWS Load
  Balancer Controller's class on EKS) and TLS (none locally; terminated at the AWS load balancer in Phase 8).

## Alternatives considered

| Option | Why not chosen |
|--------|----------------|
| Traefik bundled with k3s (Gateway API provider) | Lighter and already present, but configured through k3s's HelmChart add-on and with Gateway API as a secondary mode; Envoy Gateway is built around Gateway API as its primary model and tracks the spec closely. |
| ingress-nginx | Retired upstream. |
| NGINX Gateway Fabric | Viable; smaller community footprint for this lab's needs, no advantage over Envoy Gateway here. |
| Istio / Cilium Gateway API | Pull in a service mesh or replace the CNI: far more than an entry point needs. |
| Plain `Ingress` | Legacy API; Gateway API is the portable path to the AWS controller and supports route delegation. |

## Consequences

- Positive: routing manifests (`HTTPRoute`) are portable across environments; the platform controls which
  namespaces can be exposed; Envoy does not advertise a `Server` header; small footprint locally (~75 MiB for
  controller and proxy).
- Negative: Envoy Gateway and Gateway API CRDs are two more components to upgrade (Envoy Gateway 1.9 supports
  Kubernetes 1.33-1.36, which constrains the k3s version); Helm installs CRDs on first install only, so CRD
  upgrades need an explicit step; HTTP only in the local environment; the AWS controller's Gateway API support
  must be confirmed when Phase 8 starts.

## Verification

- `make platform-install`: Gateway `public` Accepted and Programmed; CRDs at bundle version v1.6.1.
- `make gateway-smoke`: a throwaway backend is reached through `127.0.0.1:8088` via an `HTTPRoute`, then removed.
- An `HTTPRoute` from a namespace without the label is rejected (`Accepted=False`, `NotAllowedByListeners`) and
  traffic returns 404; after labelling the namespace the same route is accepted.
- Reachable from the Windows host at `http://localhost:8088`.
