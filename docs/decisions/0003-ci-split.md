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
| Xcode Cloud "AppStore Connect + TestFlight" | Archive (iOS) → internal TestFlight | Push to `testflight` | App Store Connect workflow + `OneCart/ci_scripts/ci_post_clone.sh` |
| GitHub Actions `Release` | Validates a `vMAJOR.MINOR.PATCH` tag, then fast-forwards `release` | Push of a version tag, or manual run with `tag` | [`.github/workflows/release.yml`](../../.github/workflows/release.yml), [`scripts/promote-release.sh`](../../scripts/promote-release.sh) |
| Xcode Cloud "Release" | Archive of the tagged version for App Store Connect (+ internal TestFlight) | Push to `release` | App Store Connect workflow |

### Branch rules

1. `main` is the only branch people and agents push to (through PRs).
2. `testflight` is moved only by the `promote-testflight` job, only for a push to `main` whose
   `Tests` run passed, and only by fast-forward. PR runs never promote.
3. `release` is moved only by `scripts/promote-release.sh`, only to an annotated version tag
   whose commit is already on `testflight`, and only by fast-forward.
4. Nobody pushes, force-pushes, resets, or deletes `testflight` or `release` by hand: they
   record which commits passed the checks.
5. Only the owner creates and pushes version tags.

### Xcode Cloud settings (App Store Connect, not in the repo)

| Workflow | Start condition | Actions | Post-actions |
|----------|-----------------|---------|--------------|
| AppStore Connect + TestFlight | Branch Changes → exact branch `testflight` (not a prefix), auto-cancel on | Archive - iOS, scheme `OneCart`, App Store Connect | TestFlight Internal → Friends and Family |
| Release | Branch Changes → exact branch `release` (not a prefix), auto-cancel on | Archive - iOS, scheme `OneCart`, App Store Connect | TestFlight Internal → Friends and Family |

Neither workflow has a Test action or a `main` start condition. Changing these settings needs
the owner's approval and an update of this table in the same change.

- Runner toolchain is pinned (`Xcode_26.6`, iPhone 17 on iOS 26.5) so a runner image
  update cannot silently change the SDK under test.
- Test builds use ad-hoc signing (`CODE_SIGN_IDENTITY=-`, empty team). With
  `CODE_SIGNING_ALLOWED=NO` the test host loses Keychain access and the
  `AppleSignInTests` keychain cases fail.
- Coverage is printed with `xccov` into the job summary; it is not a gate.

### Releasing a version

1. Bump `MARKETING_VERSION` on `main` per the versioning rules in `AGENTS.md` (app and
   widget must match; the script requires exactly one value).
2. Push an annotated tag on that `main` commit: `git tag -a v1.3.0 -m "OneCart 1.3.0"`,
   then `git push origin v1.3.0`. The tag can be pushed right after the commit.
3. `Release` rejects lightweight tags, version mismatches, and commits outside `main`,
   waits up to 45 minutes for the commit to reach `testflight`, then moves `release`.
   If the checks took longer, rerun `Release` manually with the tag as input.

### Failure handling

| Symptom | Meaning | Action |
|---------|---------|--------|
| `Tests` red on `main` | `testflight` stays on the last green commit; no TestFlight build | Fix on `main`; the next green push promotes |
| `promote-testflight` push rejected | `testflight` has a commit that is not on `main` (manual push or rewritten `main`) | Stop; the owner decides how to realign — do not force-push |
| `Release` fails "not vMAJOR.MINOR.PATCH" / "annotated" / "does not match MARKETING_VERSION" / "not on main" | The tag is invalid | The owner deletes the tag and pushes a correct one |
| `Release` fails "has not reached testflight" | `Tests` for that commit is red or took over 45 minutes | Still running: wait for green, then run `Release` manually with the tag. Red: fix on `main`, bump PATCH, tag the fixed commit |
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
  submit the build from the "Release" workflow.
- `scripts/ci-boot-simulator.sh` is shared with regional-check; keep them in sync.
- Known gap: `promote-release.sh` checks that the tagged commit is an ancestor of `testflight`,
  not that its own `Tests` run passed. If a red commit is tagged and a later green commit is
  promoted, `Release` would accept the red tag. Tag only a commit whose `Tests` run is green.
