# ADR-0005: Application CI and software supply chain

- Status: Accepted
- Date: 2026-10-27

## Context

Phase 2 needs a pipeline for `taskflow-app` whose exit criteria are: every published image is traceable to a
commit, and the pipeline fails on a critical vulnerability. The lab is public (portfolio), run by one person,
on GitHub Free with no budget, and later phases deploy these images to k3d and EKS. Supply-chain incidents in
2025-2026 (moved action tags, compromised scanners) make "which code produced this image, and can we prove it"
a first-class requirement rather than an afterthought.

## Decision

### Pipeline shape

```
pull request / push to main
lint ─┐
      ├─ build and scan ──(main only)── publish (api) ─────── push :<sha> → provenance → SBOM attestation
test ─┘                                 publish (frontend)
```

| Stage | Gate (fails the build when) | Tools |
|-------|-----------------------------|-------|
| `lint` | formatting, static analysis, Dockerfile/script/workflow findings, pinned-image drift, non-executable scripts, secrets anywhere in git history (runs even if lint fails) | gofmt, go vet, golangci-lint, hadolint, shellcheck, actionlint, gitleaks |
| `test` | unit or integration test fails, or a data race is detected | `go test -race` + testcontainers PostgreSQL |
| `build and scan` | a known Go vulnerability is reachable; an image has a **CRITICAL vulnerability with a fix available** | govulncheck, docker build, Trivy; CycloneDX SBOM per image (always produced, also on failure) |
| `publish` (main only) | push or attestation fails; image `revision` label differs from the commit | docker, `actions/attest` |

Every check is a `make` target, so CI failures reproduce locally with the same command and versions.

### Policies

- **Vulnerability gate:** CRITICAL with a fix fails; HIGH is reported. Exceptions only in `.trivyignore.yaml` with
  a reason and an `expired_at` date, after which the gate fails again.
- **Build once, publish what was scanned:** `build and scan` hands the exact image archives to `publish`; nothing
  is rebuilt after the gate.
- **Tags:** full commit SHA only; no `latest`. Images carry OCI labels (`source`, `revision`, `created` = commit
  time, `version`, `description`).
- **Provenance:** SLSA build provenance and the SBOM are attested with `actions/attest` (keyless signing via
  GitHub OIDC and Sigstore, recorded in the Rekor transparency log), stored in GitHub and pushed to GHCR.
  Consumers verify with `gh attestation verify oci://… --owner TavoA2` (optionally pinning workflow and commit).
- **Pinning:** actions by commit SHA; base images by `tag@digest` (multi-arch index); linter and scanner images
  by tag (Trivy also by digest). Dependabot proposes weekly updates for Go modules, base images, the compose
  image and actions; nginx stays on its stable branch (minor/major updates ignored).
- **Least privilege:** default `GITHUB_TOKEN` read-only; write scopes (`packages`, `id-token`, `attestations`,
  `artifact-metadata`) only on the `publish` job, which runs only on `main`; scanner never gets the Docker socket;
  `persist-credentials: false`.
- **Branch protection as code:** `.github/rulesets/main.json` in each repository, applied with `make ruleset`,
  drift detected with `make ruleset-check`. Pull requests only, squash only, linear history, no force push or
  deletion, no bypass (including admins). `taskflow-app` additionally requires `lint`, `test` and
  `build and scan` from the GitHub Actions app (integration id 15368), up to date with `main`.

## Alternatives considered

| Alternative | Why not (now) |
|-------------|---------------|
| Renovate instead of Dependabot | Can also update the Makefile tool versions (regex managers), but requires installing a third-party GitHub App. Revisit if manual tool updates become a burden. |
| cosign with keys, or cosign keyless directly | `actions/attest` gives the same Sigstore keyless signing plus GitHub-native storage and `gh attestation verify`, with no keys to manage. |
| `actions/attest-build-provenance` / `attest-sbom` | Wrappers over `actions/attest`; `attest-sbom` is being deprecated. |
| Rebuild the image in the publish job | Simpler, but publishes bytes that never went through the CVE gate. |
| Gate on HIGH as well | Blocks on findings the team often cannot fix (no upstream patch), which pushes people to disable the gate. |
| Syft for SBOMs | Equivalent output; Trivy already scans the image, one tool fewer to pin and update. |
| Classic branch protection | Rulesets support restricting the source of required checks, no-bypass for admins, and are exportable as JSON. |
| Monolithic job with write permissions | One compromised step would hold registry and signing permissions on every run, including PRs. |

## Consequences

- Positive: each image in GHCR is provably linked to a commit, workflow and branch; a vulnerable base image or
  dependency blocks the merge; dependencies keep moving through the same gates; `main` cannot be changed outside
  a green PR, and drift in protection settings is detectable.
- Negative: more moving parts to keep current (Dependabot PRs every week); tool versions in the `Makefile` and
  the test PostgreSQL constant are updated manually (the latter is guarded by `check-pins`); a solo maintainer
  merges their own PRs (no second reviewer); the `publish` job only runs on `main`, so its first execution after a
  change is the real test (see Phase 2 findings).

## Verification

Evidence: [Phase 2 test results](../test-results/phase-2-app-ci.md). Gates proven by green → deliberately red →
green runs; attestations verified for published images, including a rejected verification against another commit;
ruleset negative tests rejected by GitHub.
