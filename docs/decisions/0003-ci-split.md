# ADR 0003: GitHub Actions runs tests, Xcode Cloud ships builds

Status: accepted by the owner, 2026-09-16. Supersedes **NC09** (Xcode Cloud as the only CI).
Rollout: `Test - iOS` was removed from Xcode Cloud after the first green run on `main`.
Amended 2026-09-17: Xcode Cloud starts from CI-moved `testflight` and `release` branches
instead of `main`. The scheme was first verified end to end in regional-check.

## Context

Tests ran only inside the Xcode Cloud workflow, before Archive. That spends the
25 monthly ADP compute hours on every test run, reports results only in App Store
Connect, and gives pull requests no check. The sibling app regional-check already
split CI this way and runs green on hosted `macos-26` runners.

## Decision

| System | Owns | Trigger | Config |
|--------|------|---------|--------|
| GitHub Actions `Tests` | Build for testing, `OneCartTests`, coverage summary; then fast-forwards `testflight` | Push to `main`, pull requests (promotion only on `main`) | [`.github/workflows/tests.yml`](../../.github/workflows/tests.yml) |
| Xcode Cloud "Internal TestFlight" | Archive (iOS) → internal TestFlight | Push to `testflight` | App Store Connect workflow + `OneCart/ci_scripts/ci_post_clone.sh` |
| GitHub Actions `Release` | Validates a `vMAJOR.MINOR.PATCH` tag, then fast-forwards `release` | Push of a version tag, or manual run with `tag` | [`.github/workflows/release.yml`](../../.github/workflows/release.yml), [`scripts/promote-release.sh`](../../scripts/promote-release.sh) |
| Xcode Cloud "App Store Release" | Archive of the tagged version for App Store Connect (+ internal TestFlight) | Push to `release` | App Store Connect workflow |

### Branch rules

1. `main` is the only branch people and agents push to (through PRs).
2. `testflight` is moved only by the `promote-testflight` job, only for a push to `main` whose
   `Tests` run passed, and only by fast-forward. PR runs never promote.
3. `release` is moved only by `scripts/promote-release.sh`, only to an annotated version tag
   whose exact commit has a successful `Tests` run for a push to `main` (and is therefore on
   `testflight`), and only by fast-forward.
4. Nobody pushes, force-pushes, resets, or deletes `testflight` or `release` by hand: they
   record which commits passed the checks.
5. Only the owner creates and pushes version tags.

### Xcode Cloud settings (App Store Connect, not in the repo)

| Workflow | Description | Start condition | Actions | Post-actions |
|----------|-------------|-----------------|---------|--------------|
| Internal TestFlight | Archives each commit that passed GitHub Actions Tests (CI-moved testflight branch) and uploads it to internal TestFlight (Friends and Family). No tests here. | Branch Changes → exact branch `testflight` (not a prefix), auto-cancel on | Archive - iOS, scheme `OneCart`, App Store Connect | TestFlight Internal → Friends and Family |
| App Store Release | Archives the version-tagged commit (CI-moved release branch, vMAJOR.MINOR.PATCH) for App Store Connect submission; also uploads to internal TestFlight. | Branch Changes → exact branch `release` (not a prefix), auto-cancel on | Archive - iOS, scheme `OneCart`, App Store Connect | TestFlight Internal → Friends and Family |

Names and descriptions state what each workflow does, not how it was created. Neither
workflow has a Test action or a `main` start condition. Changing these settings needs
the owner's approval and an update of this table in the same change.

- Runner toolchain is pinned (`Xcode_26.6`, iPhone 17 on iOS 26.5) so a runner image
  update cannot silently change the SDK under test.
- Test builds use ad-hoc signing (`CODE_SIGN_IDENTITY=-`, empty team). With
  `CODE_SIGNING_ALLOWED=NO` the test host loses Keychain access and the
  `AppleSignInTests` keychain cases fail.
- Coverage is printed with `xccov` into the job summary; it is not a gate.
- Pull request runs cancel superseded runs; push runs on `main` never do (one concurrency group
  per commit), so every commit pushed to `main` gets a finished `Tests` run a tag can rely on.

### Releasing a version

1. Bump `MARKETING_VERSION` on `main` per the versioning rules in `AGENTS.md` (app and
   widget must match; the script requires exactly one value).
2. Push an annotated tag on that `main` commit: `git tag -a v1.3.0 -m "OneCart 1.3.0"`,
   then `git push origin v1.3.0`. The tag can be pushed right after the commit.
3. `Release` rejects lightweight tags, version mismatches, and commits outside `main`,
   waits up to 45 minutes for a successful `Tests` run of that exact commit, confirms it is on
   `testflight`, then moves `release`. If the checks took longer, rerun `Release` manually
   with the tag as input.
4. Tag the commit that was pushed to `main` (for a PR, the merge commit). A commit inside a
   multi-commit push has no `Tests` run of its own and is rejected.

### Failure handling

| Symptom | Meaning | Action |
|---------|---------|--------|
| `Tests` red on `main` | `testflight` stays on the last green commit; no TestFlight build | Fix on `main`; the next green push promotes |
| `promote-testflight` push rejected | `testflight` has a commit that is not on `main` (manual push or rewritten `main`) | Stop; the owner decides how to realign — do not force-push |
| `Release` fails "not vMAJOR.MINOR.PATCH" / "annotated" / "does not match MARKETING_VERSION" / "not on main" | The tag is invalid | The owner deletes the tag and pushes a correct one |
| `Release` fails "Tests failed" | `Tests` for the tagged commit is red | Fix on `main`, bump PATCH, tag the fixed commit |
| `Release` fails "no successful Tests run" | `Tests` still running after 45 minutes, or the tag is on a commit without its own run | Still running: wait for green, then run `Release` manually with the tag. No run: the owner moves the tag to the pushed commit |
| `Release` fails "was cancelled" | The `Tests` run of the tagged commit was cancelled (manually, or before PR-only cancellation was introduced) | `gh run rerun <run id>`; when it is green, run `Release` manually with the tag |
| `Release` fails "passed Tests but is not on testflight" | `promote-testflight` failed in that run | Check that job; see the `promote-testflight` row |
| `Release` succeeds with "release already contains" | The tag is older than `release` (an older tag after a newer one) | Nothing to do; releases only move forward |
| `Release` push rejected | `release` has a commit that is not an ancestor of the tag (manual push) | Stop; the owner decides how to realign — do not force-push |

## Rejected alternatives

- **Keep tests in Xcode Cloud only** — no PR checks and test time counts against compute hours.
- **Test in both systems permanently** — duplicate cost, and two sources of truth for a red build.
- **SonarQube Cloud now** — the owner declined for OneCart; it needs a project, token and disabled
  Automatic Analysis. Add a `sonar` job later following regional-check.
- **Xcode Cloud starting from `main`** — it archived and uploaded every push before GitHub
  Actions finished, so untested builds could reach TestFlight.
- **DerivedData cache** — the project has no Swift packages, so there is no expensive
  dependency build to reuse.

## Consequences

- A red `Tests` run on `main` leaves `testflight` where it was, so no TestFlight build
  is made from that commit.
- A release tag builds twice in Xcode Cloud if its commit was also a `testflight` build;
  submit the build from the "App Store Release" workflow.
- `scripts/ci-boot-simulator.sh` is shared with regional-check; keep them in sync.
- `Release` checks the `Tests` run of the tagged commit itself (GitHub API, `actions: read`), not
  only ancestry of `testflight`: a later green commit would otherwise let a red tagged commit
  through.
