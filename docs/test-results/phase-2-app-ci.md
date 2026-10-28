# Phase 2 - Application CI

- Date: 2026-10-27 / 2026-10-28 (UTC)
- Result: **PASS** (both exit criteria met)
- Repository: [TavoA2/taskflow-app](https://github.com/TavoA2/taskflow-app), `main` at `c8bd679`
- Design: [ADR-0005](../adr/0005-app-ci-and-supply-chain.md)
- Raw output of the final verification: [phase-2-app-ci.log](phase-2-app-ci.log)

## Exit criteria

| Criterion | Evidence | Result |
|-----------|----------|--------|
| Image in GHCR traceable to a commit | `gh attestation verify` succeeds for both images of `c8bd679` with workflow, branch and commit pinned; verification against another commit is rejected | PASS |
| Pipeline fails on a critical CVE | PR #2: frontend base switched to `nginx-unprivileged:1.25.3-alpine` → `build and scan` failed at the CVE gate on CVE-2024-45491, CVE-2024-45492, CVE-2024-56171; reverted → green | PASS |

## How the pipeline was built and proven

Each control was introduced in its own pull request and proven by a **green → deliberately red → green** sequence,
so every gate is known to fail when it should, at the step where it should.

| Step | PR | Control | Red test (run) | Failed at |
|------|----|---------|----------------|-----------|
| 2.3 | #1 | Lint + tests (race detector) | unused function (`40571814095`) | `Lint` step only; `test` green |
| 2.4 | #2 | Build, govulncheck, CVE gate, SBOM | vulnerable nginx base (`40576997618`) | `Vulnerability report and CVE gate (Trivy)`; SBOM still uploaded |
| 2.5 | #3, #4 | Publish to GHCR + attestations | n/a (main only); see findings | |
| 2.6 | #5, #8, #9 | Dependabot, digest pins, rulesets | direct push, force push, merge without checks, `--admin` merge | all rejected by GitHub (`GH013`, `BLOCKED`) |

Green runs before and after each red test: `40569342799` / `40573243991` (PR #1), `40575912248` / `40584272265` (PR #2).

## Published images (final verification, `main` = `c8bd679`)

| | `taskflow-api` | `taskflow-frontend` |
|-|----------------|---------------------|
| Reference | `ghcr.io/tavoa2/taskflow-api:c8bd679006b8…` | `ghcr.io/tavoa2/taskflow-frontend:c8bd679006b8…` |
| Digest | `sha256:f46bab3aae90…` | `sha256:b422aa5508db…` |
| Anonymous pull (public) | yes | yes |
| `latest` tag | none | none |
| SLSA provenance | verified: repo `TavoA2/taskflow-app`, `refs/heads/main`, commit `c8bd679`, `ci.yml`, trigger `push` | verified, same |
| SBOM attestation | verified, CycloneDX, 29 components | verified, CycloneDX, 71 components |
| Signed subject = registry digest | yes | yes |
| Verification against another commit | rejected | rejected |
| Runs as | UID 65532 (numeric, `runAsNonRoot`-compatible) | UID 101 |
| CVE report | 0 vulnerabilities | 3 HIGH, 0 CRITICAL (curl, libcurl, brotli-libs in the nginx base) |

Every push to `main` since the publish job exists has produced a pair of attested images; the packages hold one tag
per published commit (`4652b85`, `09c8738`, `ecb6daf`, `ba53ba3`, `c8bd679`).

## Protection of `main`

| Test (taskflow-app) | GitHub response |
|---------------------|-----------------|
| Direct push of a commit | Rejected `GH013`: changes must be made through a pull request; 3 of 3 required status checks expected |
| Force push (guarded with `--force-with-lease`) | Rejected `GH013`: cannot force-push to this branch |
| Merge of a PR without green checks (PR #7) | `BLOCKED`: base branch policy prohibits the merge |
| Same merge with `--admin` | Rejected: repository rule violations (no bypass) |
| Direct push to `taskflow-platform` | Rejected `GH013` |

`main` was unchanged after every test. Both rulesets match their JSON files (`make ruleset-check`). Required checks
are restricted to the GitHub Actions app, so another installed app cannot satisfy them with a same-named check.

## Repository settings (both repositories)

Public; squash merge only; branches deleted on merge; secret scanning and push protection enabled; Dependabot alerts
and security updates enabled; default `GITHUB_TOKEN` read-only and unable to approve pull requests. All workflow
actions are pinned to commit SHAs (0 tag-only references); base images are pinned as `tag@digest`.

## Findings fixed during Phase 2

| Finding | How it was found | Fix |
|---------|------------------|-----|
| API image ran as `USER nonroot` (name): Kubernetes `runAsNonRoot` cannot verify a name | hadolint DL3066 | `USER 65532:65532` |
| A lint failure skipped the secrets scan | Red run of PR #1 | Secrets scan runs with `if: !cancelled()` |
| SBOM artifact named after GitHub's temporary PR merge commit (exists in no branch) | Reading artifact names on PR #2 | Name artifacts after the PR head SHA |
| Frontend image inherited nginx's OCI labels (description, url, version) | Inspecting labels before the first publish | Labels set explicitly for both images |
| First publish: `publish (frontend)` got `denied` from GHCR | First run on `main` (`40594142868`) | Diagnosed as GHCR's first-push race on a brand-new package (package created by that same push, linked to the repo); re-running the job on the same commit and archives published it |
| `fail-fast` cancelled the sibling publish job; a cancel between push and attestation would leave an unattested image | Same run: `publish (api)` cancelled after attesting | `fail-fast: false` (PR #4) |
| `smoke-test.sh` and `persistence-test.sh` lost the executable bit (edited through a Windows path) | Local verification in step 2.6 | Restored to 100755; `make lint` fails on non-executable scripts |
| Ruleset JSON did not declare two parameters GitHub fills in | `make ruleset-check` right after the first apply | Declared with GitHub's defaults (PR #8) |
| Dependabot proposed nginx 1.31 (mainline) although CI was green | Dependabot's first PR (#6) | Policy: ignore nginx minor/major; PR closed with an explanation (PR #9) |
| `actions/attest-sbom` is being deprecated | Reading the action README before use | Use `actions/attest` directly |

## Limitations

- **govulncheck has not been proven red**: forcing it requires Go code that actually calls a vulnerable function.
  Its configuration is exercised on every run, but a failing case has not been demonstrated.
- **The publish job runs only on `main`**: pull requests cannot exercise it. A local dry run against a throwaway
  registry validated push and digest handling, but not GHCR's package-creation behaviour, which only surfaced on
  the first real publish.
- **Not updated by Dependabot**: linter/scanner image versions and govulncheck in the `Makefile`, and the test
  PostgreSQL constant (guarded by `check-pins`). Reviewed manually.
- **Single maintainer**: required approvals are 0 because GitHub does not allow approving one's own PR; review is
  self-review plus automated gates.
- **Frontend carries 3 HIGH vulnerabilities** from its base image (reported, not gated by policy). `curl` is unused
  and its removal would drop two of them; tracked as a follow-up.
- **Verification is by `gh attestation verify`**, not yet enforced at deploy time; admission control in the cluster
  (Phase 5) would make unsigned images impossible to run.
