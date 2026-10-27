# Architecture Decision Records

Each significant, hard-to-reverse decision is recorded as an ADR: one file, numbered, never deleted.
A decision that changes is **superseded** by a new ADR (the old one is kept and marked as such).

| ADR | Title | Status |
|-----|-------|--------|
| [0001](0001-repo-structure.md) | Two repositories: application and platform | Accepted |
| [0002](0002-local-runtime.md) | k3d as the local Kubernetes runtime | Accepted |
| 0003 | Gateway API implementation for local (Envoy Gateway vs Traefik) | Planned (Phase 3) |

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
