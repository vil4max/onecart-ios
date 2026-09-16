# ADR 0003: GitHub Actions runs tests, Xcode Cloud ships builds

Status: accepted by the owner, 2026-09-16. Supersedes **NC09** (Xcode Cloud as the only CI).
Rollout: the Xcode Cloud `Test - iOS` action is removed only after the first green
GitHub Actions run on `main`; until then both systems test.

## Context

Tests ran only inside the Xcode Cloud workflow, before Archive. That spends the
25 monthly ADP compute hours on every test run, reports results only in App Store
Connect, and gives pull requests no check. The sibling app regional-check already
split CI this way and runs green on hosted `macos-26` runners.

## Decision

| System | Owns | Trigger | Config |
|--------|------|---------|--------|
| GitHub Actions | Build for testing, `OneCartTests`, coverage summary | Push to `main`, pull requests | [`.github/workflows/tests.yml`](../../.github/workflows/tests.yml) |
| Xcode Cloud | Archive (iOS) → internal TestFlight, build number | Push to `main` | App Store Connect workflow + `OneCart/ci_scripts/ci_post_clone.sh` |

- Runner toolchain is pinned (`Xcode_26.6`, iPhone 17 on iOS 26.5) so a runner image
  update cannot silently change the SDK under test.
- Test builds use ad-hoc signing (`CODE_SIGN_IDENTITY=-`, empty team). With
  `CODE_SIGNING_ALLOWED=NO` the test host loses Keychain access and the
  `AppleSignInTests` keychain cases fail.
- Coverage is printed with `xccov` into the job summary; it is not a gate.

## Rejected alternatives

- **Keep tests in Xcode Cloud only** — no PR checks and test time counts against compute hours.
- **Test in both systems permanently** — duplicate cost, and two sources of truth for a red build.
- **SonarQube Cloud now** — the owner declined for OneCart; it needs a project, token and disabled
  Automatic Analysis. Add a `sonar` job later following regional-check.
- **DerivedData cache** — the project has no Swift packages, so there is no expensive
  dependency build to reuse.

## Consequences

- A red `Tests` check on `main` does not block Xcode Cloud from archiving; check the
  Actions run before selecting a TestFlight build for submission.
- `scripts/ci-boot-simulator.sh` is shared with regional-check; keep them in sync.
