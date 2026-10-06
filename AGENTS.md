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
- Build and CI tooling lives in `Tooling/`; configuration is in
  [`Tooling/runtime.yml`](Tooling/runtime.yml):

  ```yaml
  scheme: OneCart
  project: OneCart/OneCart.xcodeproj
  ```

- Style: `Tooling/.swiftlint.yml` and `Tooling/.swift-format` (Apple's swift-format, which ships
  with the Xcode toolchain) are managed by the shared tooling and identical in every iOS app;
  `just baseline` fails on drift ([`Tooling/docs/style-config.md`](Tooling/docs/style-config.md)).
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
| `Tooling/` | Shared build and CI tooling — see [Tooling/README.md](Tooling/README.md) |
| `justfile` | Imports `Tooling/justfile` and adds the `demo` recipes |
| `scripts/smoke-tests.sh` | Runs `just test` |

## Commands

```bash
brew bundle --file=Tooling/Brewfile
just doctor
just diagnose
just build
just test
just verify          # definition of done: lint, build, unit and UI tests
just run-sim
just demo role=owner
just demo-tab role=member tab=cart
```

The repository has no git hooks. The tests, UI smoke tests included, run in `just verify` and in
the CI `Tests` workflow (`just ci`).

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
Cloud only archives, and tags, not pushes, request builds. Both workflows are the shared
templates, identical in every app: [`Tooling/docs/ci.md`](Tooling/docs/ci.md),
[`Tooling/docs/testflight.md`](Tooling/docs/testflight.md).

- `main` is development. `Tests` (`.github/workflows/tests.yml`) runs on every push and pull
  request and publishes nothing.
- `testflight` is moved only by the `TestFlight` workflow (`.github/workflows/testflight.yml`), on
  an annotated `tf-MAJOR.MINOR.PATCH-BUILD` tag, only by fast-forward. `release` is frozen at
  `v1.2.1`. Never push, force-push, reset, or delete either branch.
- A `tf-` tag is created for a commit already on `origin/main` after `just tf-check` prints
  `Ready`. The annotation is the round's What to Test. Push a release-prep commit as the head of
  its push: only that commit gets its own `Tests` run and can be tagged.
- `v` tags and the App Review submission belong to the maintainer.
- Branches and worktrees exist only while work is in progress; delete merged branches locally and
  on GitHub. Permanent branches are `main`, `testflight` and `release`. Leave no build artifacts
  in the working tree.
- Xcode Cloud workflow settings live in App Store Connect, not in the repo; changing them
  requires updating ADR 0003 in the same change.
