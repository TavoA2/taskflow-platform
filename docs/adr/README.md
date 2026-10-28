# Architecture Decision Records

Each significant, hard-to-reverse decision is recorded as an ADR: one file, numbered, never deleted.
A decision that changes is **superseded** by a new ADR (the old one is kept and marked as such).
Numbers are assigned when an ADR is written, not reserved in advance for planned decisions.

| ADR | Title | Status |
|-----|-------|--------|
| [0001](0001-repo-structure.md) | Two repositories: application and platform | Accepted |
| [0002](0002-local-runtime.md) | k3d as the local Kubernetes runtime | Accepted |
| [0003](0003-api-stack.md) | Go API stack | Accepted |
| [0004](0004-database-migrations.md) | Database migrations strategy | Accepted |
| [0005](0005-app-ci-and-supply-chain.md) | Application CI and software supply chain | Accepted |

Planned (not yet numbered): Gateway API implementation for local (Envoy Gateway vs Traefik), Phase 3.

## Template

```markdown
# ADR-NNNN: <title>

- Status: Proposed | Accepted | Superseded by ADR-XXXX
- Date: YYYY-MM-DD

## Context
## Decision
## Alternatives considered
## Consequences
## Verification
```
