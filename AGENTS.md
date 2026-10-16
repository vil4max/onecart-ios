# OneCart

OneCart Family is an iPhone app for one shared family shopping cart: items are added by name,
checked off in the store, and archived into History by day. Sync and invites run through
iCloud / CloudKit (`CKShare`); sign-in is Sign in with Apple.

This repository is public: keep credentials, tokens, personal data and machine-specific paths
out of source, documentation and commit messages, and use fictional data in examples and tests.

## Project

- Open `OneCart/OneCart.xcodeproj` (scheme `OneCart`).
- Supported devices: iPhone only (`TARGETED_DEVICE_FAMILY = 1`); keep app, widget, and test
  targets aligned.
- The gate is `ios-verify` from the ios-dev Claude Code plugin, enabled at local scope (the
  plugin's README covers install and every subcommand). Its configuration is
  [`ios-verify.conf`](ios-verify.conf): scheme `OneCart`, project `OneCart/OneCart.xcodeproj`,
  simulator iPhone 17 on iOS 27.0, `device_family=1`, and the App Group the app and the widget
  extension share. Each worktree gets its own simulators; `.worktreeinclude` copies the local
  plugin settings into new worktrees.
- Style: the root [`.swiftlint.yml`](.swiftlint.yml) and [`.swift-format`](.swift-format)
  (Apple's swift-format, which ships with the Xcode toolchain) start from the plugin's
  `config/` limits. [`.swiftlint.baseline.json`](.swiftlint.baseline.json) records the
  size-limit violations the code had when the limits were adopted; only new ones fail.
  Re-record it with `ios-verify baseline` (never `swiftlint --write-baseline`, which stores
  absolute paths) in the same commit that changes a baselined type or function, and do not
  raise a limit instead. `.swiftlint-version` pins SwiftLint for CI.
- Documentation index: [docs/README.md](docs/README.md).

## Folder structure

| Path | Role |
|------|------|
| `OneCart/Application/` | Composition root (`AppSession`, `CartSyncService`, `FamilyShareOrchestrator`) |
| `OneCart/Features/` | Feature Views + ViewModels (`Shopping/`, `Account/`, `Onboarding/`) |
| `OneCart/Data/` | Persistence, CloudKit, Auth |
| `OneCart/Shared/` | Cross-feature helpers |
| `OneCart/OneCartWidgets/` | Widgets and Live Activity |
| `OneCart/Resources/` | Bundle resources |
| `OneCart/Tests/` | Unit tests (`OneCartTests` target) |
| `OneCart/OneCartUITests/` | UI smoke tests |
| `docs/` | Core goals, requirements, decisions, architecture, release runbook |
| `assets/` | Brand / store masters (not in the app bundle) |
| `OneCart/ci_scripts/` | Xcode Cloud `ci_post_clone.sh` and the TestFlight tag scripts (`tf-check.sh`, `tf-promote.sh`) |
| `ios-verify.conf` | Configuration of the `ios-verify` gate |

## Commands

```bash
brew install swiftlint            # the version in .swiftlint-version; ios-verify warns on a mismatch
ios-verify                        # definition of done: project checks, lint, build, unit and UI smoke tests
ios-verify --only-testing OneCartTests/SomeSuite   # one test while working (no lint, no checks)
ios-verify lint [--all] [--fix]   # swift-format and SwiftLint only
ios-verify run-sim                # the seeded owner demo cart on this worktree's run simulator
ios-verify run-sim -- -oneCartDemoUI -oneCartDemoRole member -oneCartDemoTab cart
OneCart/ci_scripts/tf-check.sh    # read-only TestFlight tag check
```

The OneCart scheme's Test action holds both `OneCartTests` and the `OneCartUITests` smoke
suite, so `ios-verify` runs both; there is no separate UI scheme. Run the full gate in the
background: it takes several minutes. Logs and result bundles stay in `build/verify/`. When a
worktree goes, delete its `ios-verify OneCart <worktree>` simulators (`xcrun simctl delete`).

The repository has no git hooks. The CI `Tests` workflow calls Apple's tools and the two linters
directly with the same committed configuration.

## Code and test conventions

- Architecture: MVVM with protocol-based services, no Coordinator and no Clean Domain layer; see
  [docs/engineering/architecture.md](docs/engineering/architecture.md).
- Behavior is specified in [docs/requirements/product.md](docs/requirements/product.md) as
  `REQ-<AREA>-NNN` requirements; the goals behind them are in [docs/core.md](docs/core.md).
  Tests are named after the requirement they prove: XCTest `test_REQ_<AREA>_<NNN>_…`, Swift
  Testing `@Test("REQ-<AREA>-<NNN>: …")`.
- A bug starts with a failing test that carries the requirement ID, then the fix. Record a
  regression note in [docs/lessons.md](docs/lessons.md) only when a check or an upper layer
  changed.
- Stability first: do not restore Stores, catalog, price UI or rich product forms. The core path
  is Sign in with Apple → one living cart → name-only add → Completed → overnight History by day
  → invite from Settings.
- Comments explain intent, invariants and constraints that the code cannot carry.

## Versioning

- Marketing versions use `MAJOR.MINOR.PATCH`, with all three components treated as integers.
- A feature release increments MINOR and resets PATCH to `0`; a fix-only release with no new
  features increments PATCH instead. Do not roll MAJOR without an explicit request.
- The build number is separate: reset it to `1` for a new marketing version, then increment
  within that version.
- Keep the app and widget extension versions and build numbers aligned in Debug and Release.

## CI and releases

Decisions: [ADR 0003](docs/decisions/0003-ci-split.md) and
[ADR 0004](docs/decisions/0004-tag-gated-testflight.md). GitHub Actions runs the tests, Xcode
Cloud only archives, and tags, not pushes, request builds. The workflows and the scripts in
`OneCart/ci_scripts/` are this repository's own copies of the ios-dev plugin's reference CI
templates; nothing from the plugin runs in CI.

- `main` is development. `Tests` (`.github/workflows/tests.yml`) runs on every push and pull
  request and publishes nothing: swift-format and SwiftLint over every tracked Swift file, then
  `xcodebuild build test` of the `OneCart` scheme (unit and UI smoke tests).
- `testflight` is moved only by the `TestFlight` workflow (`.github/workflows/testflight.yml`,
  which runs `OneCart/ci_scripts/tf-promote.sh`), on an annotated `tf-MAJOR.MINOR.PATCH-BUILD`
  tag, only by fast-forward. `release` is frozen at `v1.2.1`. Never push, force-push, reset, or
  delete either branch.
- A `tf-` tag is created for a commit already on `origin/main` after
  `OneCart/ci_scripts/tf-check.sh` prints `Ready`. The annotation is the round's What to Test. Push a release-prep commit as the head of
  its push: only that commit gets its own `Tests` run and can be tagged.
- `v` tags and the App Review submission belong to the maintainer.
- Branches and worktrees exist only while work is in progress; delete merged branches locally and
  on GitHub. Permanent branches are `main`, `testflight` and `release`. Leave no build artifacts
  in the working tree.
- Xcode Cloud workflow settings live in App Store Connect, not in the repo; changing them
  requires updating ADR 0003 in the same change.
