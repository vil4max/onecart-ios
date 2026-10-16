# ADR 0003: GitHub Actions runs tests, Xcode Cloud ships builds

Status: accepted. Supersedes the earlier arrangement in which Xcode Cloud was the only CI.

[ADR 0004](0004-tag-gated-testflight.md) refines the promotion rules: `Tests` promotes nothing,
`tf-` tags request TestFlight builds, `v` tags only mark the submitted commit, and nothing moves
`release`. The tables and rules below reflect that model; the procedure is in ADR 0004 and the
TestFlight section of [`docs/operations/release.md`](../operations/release.md).

Mechanism update (2026-10-16): the shared `Tooling/` copy and its `just ci` entry point are
gone. The decision is unchanged; `Tests` now calls Apple's tools and the two linters directly,
the TestFlight scripts live in `OneCart/ci_scripts/`, and the local gate is the ios-dev
plugin's `ios-verify`.

## Context

Tests used to run only inside the Xcode Cloud workflow, before Archive. That spends the
25 monthly Apple Developer Program compute hours on every test run, reports results only in App
Store Connect, and gives pull requests no check.

The app's minimum OS is iOS 27, so `Tests` runs on the public-preview `xcode-27` runner image
(see [Runner image risk](#runner-image-risk-xcode-27-is-a-public-preview)).

## Decision

| System | Owns | Trigger | Config |
|--------|------|---------|--------|
| GitHub Actions `Tests` | swift-format and SwiftLint over every tracked Swift file, build, `OneCartTests` and the `OneCartUITests` smoke tests (both in the `OneCart` scheme), test count and coverage summary; promotes nothing | Push to `main`, pull requests | [`.github/workflows/tests.yml`](../../.github/workflows/tests.yml) |
| GitHub Actions `TestFlight` | Checks a `tf-` tag and fast-forwards `testflight`, or checks that a `v` tag marks a commit with its own `tf-` round | Push of a `tf-*` or `v*.*.*` tag, or manual run with `tag` | [`.github/workflows/testflight.yml`](../../.github/workflows/testflight.yml), `OneCart/ci_scripts/tf-promote.sh` |
| Xcode Cloud "Internal TestFlight (verified main)" | Archive (iOS) → internal TestFlight | Push to `testflight` | App Store Connect workflow + `OneCart/ci_scripts/ci_post_clone.sh` |
| Xcode Cloud "App Store candidate (release tag)" | Deactivated (ADR 0004): no build starts from it; turning it back on in App Store Connect would resume builds from `release` | Push to `release` | App Store Connect workflow |

### Branch rules

1. `main` is the only branch people push to (through pull requests).
2. `testflight` is moved only by `OneCart/ci_scripts/tf-promote.sh`, only to an annotated
   `tf-MAJOR.MINOR.PATCH-BUILD` tag whose exact commit is on `main`, is built as that version,
   and has a successful `Tests` run for a push to `main`, and only by fast-forward.
3. `release` is no longer moved. It stays at the commit tagged `v1.2.1`.
4. Nobody pushes, force-pushes, resets, or deletes `testflight` or `release` by hand: they
   record which commits passed the checks.
5. The maintainer creates and pushes `v` tags and submits for App Review; `AGENTS.md` records who
   may create `tf-` tags.

### Xcode Cloud settings (App Store Connect, not in the repo)

| Workflow | Description | Start condition | Actions | Post-actions |
|----------|-------------|-----------------|---------|--------------|
| Internal TestFlight (verified main) | Archives the commit of a verified tf-MAJOR.MINOR.PATCH-BUILD tag (testflight.yml fast-forwards the testflight branch) and uploads it to TestFlight internal testing, group Friends and Family. An App Store submission is one of these builds. Does not run tests. Restrict Editing on. | Branch Changes → exact branch `testflight` (not a prefix), auto-cancel on | Archive - iOS, scheme `OneCart`, Distribution Preparation "App Store Connect" | TestFlight Internal → Friends and Family |
| App Store candidate (release tag) | **Deactivated.** Formerly archived the commit of a verified vMAJOR.MINOR.PATCH tag from the release branch. | Branch Changes → exact branch `release` (not a prefix), auto-cancel on | Archive - iOS, scheme `OneCart`, App Store Connect | TestFlight Internal → Friends and Family |

The primary repository of the remaining workflow is `https://github.com/vil4max/onecart-ios.git`.
The web editor calls the Distribution Preparation option "App Store Connect" ("Eligible for
distribution to all testers and customers"); Apple's Xcode documentation calls the same option
"TestFlight and App Store". The other choices are None and "TestFlight (Internal Testing Only)".
Clean is off. Names and descriptions say which commits each workflow builds (verified `main`,
release tag). Neither workflow has a Test action or a `main` start condition. Changing these
settings requires an update of this table in the same change.

- `Tests` is this repository's copy of the ios-dev plugin's reference workflow (since
  2026-10-16; before, the shared `Tooling/` template ran `just ci`). It calls `xcrun
  swift-format`, `swiftlint` and `xcodebuild` directly with the committed `.swift-format`,
  `.swiftlint.yml` and `.swiftlint.baseline.json`, and pins every action by commit. SwiftLint
  is pinned by `.swiftlint-version` (version and release checksum), because the baseline
  matches violations by their text. Project, scheme and destination default to this app's
  values; repository variables override them.
- Runner toolchain is pinned by the workflow's defaults — runner `xcode-27`, `DEVELOPER_DIR`
  `/Applications/Xcode_27.0.app/Contents/Developer`, destination `iPhone 17` — so a runner image
  update cannot silently change the SDK under test. The versioned `Xcode_27.0.app` path fails
  the job if the image later defaults to another Xcode. `IOS_RUNNER` and `IOS_DEVELOPER_DIR`
  override them.
- `Tests` signs ad hoc (`CODE_SIGN_IDENTITY=-`). With `CODE_SIGNING_ALLOWED=NO` the test host
  loses Keychain access and the `AppleSignInTests` keychain cases fail, which is why ad-hoc
  signing is the default.
- The executed-test count is read from the result bundle; a run where no test executed fails.
  Coverage is printed with `xccov` into the job summary; it is not a gate.
- Pull request runs cancel superseded runs; push runs on `main` never do (one concurrency group
  per commit), so every commit pushed to `main` gets a finished `Tests` run a tag can rely on.

### Runner image risk: `xcode-27` is a public preview

`IPHONEOS_DEPLOYMENT_TARGET` is 27.0, so `Tests` needs the iOS 27 SDK, and no generally
available GitHub-hosted image carries one. Checked against
[the runner-images README](https://github.com/actions/runner-images/blob/main/README.md) and
[the preview announcement](https://github.com/actions/runner-images/issues/14404):

- `macos-26` (GA, arm64) installs Xcode 26.0.1 … 26.6 and iOS 26.2 / 26.4 / 26.5 runtimes only.
- `xcode-27` (arm64) is the only label with Xcode 27, and it is published as a **public preview**:
  image `20260912.0186.1`, macOS 27.0, default Xcode 27.0 build `27A266a`, iOS 27.0 simulator
  runtime, `iPhone 17` among the available devices.
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

As soon as a GA label ships Xcode 27, set the `IOS_RUNNER` and `IOS_DEVELOPER_DIR` repository
variables to it.

### Releasing a version and failure handling

The round procedure, the release steps and the failure handling are in
[ADR 0004](0004-tag-gated-testflight.md) and the TestFlight section of
[`docs/operations/release.md`](../operations/release.md). A `Tests` run that fails to start on
every commit means the `xcode-27` image or its `Xcode_27.0` path is gone — see
[Runner image risk](#runner-image-risk-xcode-27-is-a-public-preview).

## Rejected alternatives

- **Keep tests in Xcode Cloud only** — no PR checks and test time counts against compute hours.
- **Test in both systems permanently** — duplicate cost, and two sources of truth for a red build.
- **SonarQube Cloud in CI** — it needs a project, token and disabled Automatic Analysis for no
  measured gain here.
- **Xcode Cloud starting from `main`** — it archived and uploaded every push before GitHub
  Actions finished, so untested builds could reach TestFlight.
- **DerivedData cache** — the project has no Swift packages, so there is no expensive
  dependency build to reuse.

## Consequences

- A red `Tests` run on `main` publishes nothing, and a `tf-` tag on that commit is rejected.
- `Tests` and the local `ios-verify` gate lint with the same committed configuration and run the
  same scheme; `ios-verify` additionally checks the device family and App Group entitlements
  for every build configuration.
- The tag checks read the `Tests` run of the tagged commit itself (GitHub API, `actions: read`),
  not only ancestry of `testflight`: a later green commit would otherwise let a red tagged
  commit through.
