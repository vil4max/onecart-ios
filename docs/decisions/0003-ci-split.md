# ADR 0003: GitHub Actions runs tests, Xcode Cloud ships builds

Status: accepted by the owner, 2026-09-16. Supersedes **NC09** (Xcode Cloud as the only CI).
Rollout: `Test - iOS` was removed from Xcode Cloud after the first green run on `main`.
Amended 2026-09-17: Xcode Cloud starts from CI-moved `testflight` and `release` branches
instead of `main`. The scheme was first verified end to end in regional-check.
Amended 2026-09-21: the app's minimum OS is iOS 27, so `Tests` moved from the GA `macos-26`
image to the public-preview `xcode-27` image — see [Runner image risk](#runner-image-risk-xcode-27-is-a-public-preview).
Superseded in part 2026-09-21 by [ADR 0004](0004-tag-gated-testflight.md): `Tests` promotes
nothing, `tf-` tags request TestFlight builds, `v` tags only mark the submitted commit, and
nothing moves `release`. The tables and rules below are updated to match; the procedure is in
[`Tooling/docs/testflight.md`](../../Tooling/docs/testflight.md).

## Context

Tests ran only inside the Xcode Cloud workflow, before Archive. That spends the
25 monthly ADP compute hours on every test run, reports results only in App Store
Connect, and gives pull requests no check. The sibling app regional-check already
split CI this way and runs green on hosted `macos-26` runners.

## Decision

| System | Owns | Trigger | Config |
|--------|------|---------|--------|
| GitHub Actions `Tests` | Build for testing, `OneCartTests`, coverage summary; promotes nothing | Push to `main`, pull requests | [`.github/workflows/tests.yml`](../../.github/workflows/tests.yml) |
| GitHub Actions `TestFlight` | Checks a `tf-` tag and fast-forwards `testflight`, or checks that a `v` tag marks a commit with its own `tf-` round | Push of a `tf-*` or `v*.*.*` tag, or manual run with `tag` | [`.github/workflows/testflight.yml`](../../.github/workflows/testflight.yml), `Tooling/scripts/tf-promote.sh` |
| Xcode Cloud "Internal TestFlight (verified main)" | Archive (iOS) → internal TestFlight | Push to `testflight` | App Store Connect workflow + `OneCart/ci_scripts/ci_post_clone.sh` |
| Xcode Cloud "App Store candidate (release tag)" | Unused since ADR 0004: nothing moves `release`, so it never starts. The owner retires it in App Store Connect | Push to `release` | App Store Connect workflow |

### Branch rules

1. `main` is the only branch people and agents push to (through PRs).
2. `testflight` is moved only by `Tooling/scripts/tf-promote.sh`, only to an annotated
   `tf-MAJOR.MINOR.PATCH-BUILD` tag whose exact commit is on `main`, is built as that version,
   and has a successful `Tests` run for a push to `main`, and only by fast-forward.
3. `release` is no longer moved. It stays at `a5e6915` (`v1.2.1`) until the owner retires it.
4. Nobody pushes, force-pushes, resets, or deletes `testflight` or `release` by hand: they
   record which commits passed the checks.
5. The owner creates and pushes `v` tags and submits for App Review; `tf-` tag authority is in
   `AGENTS.md`.

### Xcode Cloud settings (App Store Connect, not in the repo)

| Workflow | Description | Start condition | Actions | Post-actions |
|----------|-------------|-----------------|---------|--------------|
| Internal TestFlight (verified main) | Archives the commit of a verified tf-MAJOR.MINOR.PATCH-BUILD tag (testflight.yml fast-forwards the testflight branch) and uploads it to TestFlight internal testing, group Friends and Family. An App Store submission is one of these builds. Does not run tests. | Branch Changes → exact branch `testflight` (not a prefix), auto-cancel on | Archive - iOS, scheme `OneCart`, App Store Connect | TestFlight Internal → Friends and Family |
| App Store candidate (release tag) | Unused since ADR 0004; to be retired by the owner. Formerly archived the commit of a verified vMAJOR.MINOR.PATCH tag from the release branch. | Branch Changes → exact branch `release` (not a prefix), auto-cancel on | Archive - iOS, scheme `OneCart`, App Store Connect | TestFlight Internal → Friends and Family |

The "Internal TestFlight (verified main)" description above is the intended text after
ADR 0004; App Store Connect still shows the every-push description until the owner edits it.
Names and descriptions say which commits each workflow builds (verified `main`, release tag), matching regional-check; both share the upload mechanics, so those do not name them. Neither
workflow has a Test action or a `main` start condition. Changing these settings needs
the owner's approval and an update of this table in the same change.

- Runner toolchain is pinned (`xcode-27` image, `Xcode_27.0`, iPhone 17 on iOS 27.0) so a
  runner image update cannot silently change the SDK under test. `DEVELOPER_DIR` names the
  versioned `/Applications/Xcode_27.0.app` symlink rather than `/Applications/Xcode.app`: if the
  image later defaults to a different Xcode, the job fails instead of testing another SDK.
- Test builds use ad-hoc signing (`CODE_SIGN_IDENTITY=-`, empty team). With
  `CODE_SIGNING_ALLOWED=NO` the test host loses Keychain access and the
  `AppleSignInTests` keychain cases fail.
- Coverage is printed with `xccov` into the job summary; it is not a gate.
- Pull request runs cancel superseded runs; push runs on `main` never do (one concurrency group
  per commit), so every commit pushed to `main` gets a finished `Tests` run a tag can rely on.

### Runner image risk: `xcode-27` is a public preview

`IPHONEOS_DEPLOYMENT_TARGET` is 27.0, so `Tests` needs the iOS 27 SDK, and no generally
available GitHub-hosted image carries one. Checked 2026-09-21 against
[the runner-images README](https://github.com/actions/runner-images/blob/main/README.md) and
[the preview announcement](https://github.com/actions/runner-images/issues/14404):

- `macos-26` (GA, arm64) installs Xcode 26.0.1 … 26.6 and iOS 26.2 / 26.4 / 26.5 runtimes only.
- `xcode-27` (arm64) is the only label with Xcode 27, and it is published as a **public preview**:
  image `20260912.0186.1`, macOS 27.0, default Xcode 27.0 build `27A266a` (the same build used
  locally), iOS 27.0 simulator runtime, `iPhone 17` among the available devices.
- The announcement warns that software on the new platform can be unstable and that runner
  capacity is still being balanced, so runs may queue longer than on a GA image.

This makes the whole promotion chain depend on a preview image:

1. A preview image carries no availability guarantee. If it is withdrawn, renamed at GA, or
   re-based onto a newer Xcode so `/Applications/Xcode_27.0.app` disappears, `Tests` fails for
   every push to `main`. `tf-promote.sh` needs the tagged commit's green `Tests` run, so no
   `tf-` tag can move `testflight` and no TestFlight build is produced.
2. The same check applies to `v` tags, so a submitted commit cannot be marked either.
3. Preview queueing can push a `Tests` run past the script's 45-minute wait. Rerun
   `TestFlight` manually with the tag; do not move the tag.
4. Xcode Cloud is unaffected — it archives with its own toolchain from `testflight`.
   The exposure is the verification gate, not the build that ships.

Repin `runs-on` and `DEVELOPER_DIR` to a GA label as soon as one ships Xcode 27.

### Releasing a version and failure handling

Moved with ADR 0004: the round procedure, the release steps and the failure table are in
[`Tooling/docs/testflight.md`](../../Tooling/docs/testflight.md) and the TestFlight section of
[`docs/operations/release.md`](../operations/release.md). A `Tests` run that fails to start on
every commit still means the `xcode-27` image or its `Xcode_27.0` path is gone — see
[Runner image risk](#runner-image-risk-xcode-27-is-a-public-preview).

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

- A red `Tests` run on `main` publishes nothing, and a `tf-` tag on that commit is rejected.
- `scripts/ci-boot-simulator.sh` is shared with regional-check; keep them in sync.
- The tag checks read the `Tests` run of the tagged commit itself (GitHub API, `actions: read`),
  not only ancestry of `testflight`: a later green commit would otherwise let a red tagged
  commit through.
