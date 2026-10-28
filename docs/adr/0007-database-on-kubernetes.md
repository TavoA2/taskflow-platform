# ADR-0007: PostgreSQL, credentials and migrations on the local cluster

- Status: Accepted
- Date: 2026-10-28

## Context

Phase 3 runs TaskFlow on the local k3d cluster. The API needs PostgreSQL, a schema applied before it serves
traffic (ADR-0004: same image, `taskflow-api migrate up`), and database credentials that must never be
committed. Encrypted secrets are a Phase 5 topic; something simpler is needed now without creating habits
that are hard to undo.

## Decision

1. **PostgreSQL as a StatefulSet** in the `taskflow` namespace: one replica, a headless Service
   (`postgres.taskflow.svc.cluster.local`), a 1 GiB `ReadWriteOnce` volume from the cluster's default
   StorageClass (`local-path` on k3s). Same image and digest as `compose.yaml` in taskflow-app.
2. **Credentials from a git-ignored file** through a Kustomize `secretGenerator`
   (`gitops/overlays/local/secrets/postgres.env`, created by `make local-secrets` with a random hex password).
   Only a `*.env.example` placeholder is committed; `make validate` renders overlays with it in CI.
   This is **temporary** and is replaced in Phase 5.
3. **Migrations as a Job** (`migrate`) using the API image pinned by tag and digest. `make deploy` deletes the
   previous Job (its pod template is immutable) and waits for the new one to complete. In Phase 4 this becomes
   an ArgoCD `PreSync` hook.
4. **Pod Security Admission `restricted`** is enforced on the namespace from the start, so the API server
   rejects any pod that runs as root, keeps capabilities, allows privilege escalation or has no seccomp profile.

## Alternatives considered

| Option | Why not chosen (now) |
|--------|----------------------|
| Helm chart (e.g. Bitnami PostgreSQL) | Hides the details this lab is meant to show; extra values surface to keep pinned. |
| Operator (CloudNativePG) | Real HA, backups and failover, but heavy for a laptop and premature before Phase 7. Candidate later. |
| Managed database (RDS) | Paid; only in Phase 9 with explicit approval. |
| Plain `Secret` manifest in Git | Commits the password. Rejected outright. |
| SOPS / Sealed Secrets / External Secrets now | The right destination, decided in Phase 5 together with RBAC and NetworkPolicies. |
| Migrations in an `initContainer` of the API | Every replica would race to migrate on every start; a failure would look like an API crash. |
| Migrations at API startup | Same race, and the API would need DDL privileges at runtime. |

## Consequences

- Positive: the whole data tier is declared in Git; credentials stay on the workstation; the schema is applied
  once per deploy with a visible `Complete`/`Failed` result; insecure pods are rejected by the cluster.
- Negative / limitations (documented, not hidden):
  - **No high availability**: one PostgreSQL pod, and the `local-path` volume lives on one node's disk. Data
    survives pod restarts, not node loss. No backups yet.
  - `POSTGRES_PASSWORD` is read only when an empty volume is initialised; changing the file later does not
    change the database password (`make local-secrets` therefore never overwrites it).
  - Until ArgoCD (Phase 4) the cluster is changed by `make deploy`, a manual step.
  - The migrate Job retries while the database starts; its first attempts may log "no such host".
    `DATABASE_URL` uses the FQDN so those lookups fail fast inside the cluster domain instead of being
    forwarded to the upstream resolver, which drops single-label names (observed with Docker Desktop).

## Verification

```bash
make local-secrets && make deploy      # statefulset 1/1, PVC Bound, job/migrate Complete, "schema version 1"
make deploy                            # again: "no pending migrations"
kubectl --context k3d-taskflow -n taskflow run psa-root --image=busybox:1.37.0 --restart=Never \
  --overrides='{"spec":{"securityContext":{"runAsUser":0}}}' --command -- true
                                       # Forbidden: violates PodSecurity "restricted:v1.36"
git check-ignore -v gitops/overlays/local/secrets/postgres.env   # matched by .gitignore
```
