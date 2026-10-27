# ADR-0003: Go API stack

- Status: Accepted
- Date: 2026-10-27

## Context

The TaskFlow API exists to exercise deployment, probes, rollouts, scaling, metrics and recovery on
Kubernetes. Image size, startup time and memory footprint directly affect how fast those exercises run
on a workstation with ~8-10 GiB for the whole cluster. The author's background is Java/Spring Boot.

## Decision

Write the API in **Go**, keeping dependencies minimal:

| Concern | Choice |
|---------|--------|
| HTTP routing | Standard library `net/http` (method + path-parameter patterns) |
| PostgreSQL driver | `pgx/v5` with `pgxpool` |
| Logging | Standard library `log/slog`, JSON to stdout |
| Metrics | `prometheus/client_golang`; `route` label uses the route pattern, not the raw path |
| Configuration | Environment variables only |
| Image | Multi-stage build, static binary (`CGO_ENABLED=0`), distroless `static` base, non-root user |
| Health | `/healthz` = liveness (process only, never the database); `/readyz` = readiness (database ping, 503 while shutting down) |

The binary exposes subcommands (`serve`, `migrate`, `healthcheck`) so a single image covers the service,
its schema migrations and container health checks (distroless images have no shell or curl).

## Alternatives considered

- **Java/Spring Boot**: strongest prior experience and Actuator gives health/metrics out of the box, but
  images of 200+ MB, 5-15 s startup and JVM memory overhead slow down rollout and failure exercises.
- **Python/FastAPI**: concise, but larger images and a runtime interpreter add attack surface and CVEs to triage.
- **A Go web framework (Gin, Echo, Chi)**: not needed since stdlib routing supports path parameters;
  every dependency is one more item for vulnerability scanning.

## Consequences

- Positive: image well under 20 MB, sub-second startup, small CVE surface, explicit code for probes and
  graceful shutdown (useful to explain in interviews).
- Negative: new language for the author; less "magic" than Actuator means health, metrics and shutdown
  are written and tested by hand.

## Verification

- `docker image ls` shows the API image under 20 MB; `docker image inspect` shows a non-root user.
- Unit tests cover configuration and health handlers (`make test`).
