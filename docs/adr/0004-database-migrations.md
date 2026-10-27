# ADR-0004: Database migrations strategy

- Status: Accepted
- Date: 2026-10-27

## Context

The PostgreSQL schema must be versioned and applied reproducibly in docker compose (Phase 1), Kubernetes
(Phases 3-7) and Amazon RDS (Phase 9). During rolling updates, old and new API versions run at the same
time against the same schema.

## Decision

1. Use **goose** with SQL migration files embedded in the API binary (`embed.FS`) and run them with
   `taskflow-api migrate up`. Schema and code are versioned, built, scanned and released together.
2. Run migrations as a **separate one-shot step, never at API startup**:
   - docker compose: a `migrate` service; `api` depends on it with `service_completed_successfully`.
   - Kubernetes: a Job (an ArgoCD PreSync hook from Phase 4).
3. Every migration must be **backward compatible with the previous application version**
   (expand/contract): add columns/tables first, deploy code that uses them, and remove old structures
   only in a later release.

## Alternatives considered

- **golang-migrate with its CLI image**: equally capable, but a second image to version, scan and keep in sync.
- **Migrate on API startup**: simplest, but N replicas race for the same migration and a failing
  migration crash-loops every pod instead of failing one visible step.
- **ORM auto-migration**: not reviewable as SQL and hides destructive changes.

## Consequences

- Positive: one artifact; a failed migration blocks the deployment visibly instead of breaking running pods;
  rollouts are safe because schemas stay compatible across adjacent versions.
- Negative: destructive changes need two releases; rolling back code does not roll back the schema
  (down migrations are written but treated as an exceptional, manual operation).

## Verification

- `goose status` shows all migrations applied after `docker compose up`.
- Integration tests apply all migrations to an empty PostgreSQL before running (testcontainers-go).
