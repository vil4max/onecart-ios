# OneCart — agent notes (thin)

Project facts only. Agent behavior lives in the Cursor Brain (`agent-engineering-kit`).

## Project

- Name: OneCart
- Supported devices: iPhone only (`TARGETED_DEVICE_FAMILY = 1`); keep app, widget, and test targets aligned.
- Context: see `.cursor/project-context` (`personal`)
- Open: `OneCart/OneCart.xcodeproj`
- Runtime: `Tooling/` (ios-engineering-runtime 0.2.2)
- Docs index: [docs/README.md](docs/README.md)

## Spec pyramid

Start from [`docs/core.md`](docs/core.md) (approved 2026-09-16). Layers:
core → `docs/requirements/` + `docs/decisions/` → tests named with
`REQ-<AREA>-NNN` → code. Index: [`docs/README.md`](docs/README.md). Method:
kit skill `spec-pyramid`.

- Change starts at the highest affected layer; propose, do not approve, core
  or requirement edits.
- Bug → failing spec with a REQ ID first, then the fix.
- Record a lesson only when a check or upper layer changed:
  [`docs/lessons.md`](docs/lessons.md).

## Review

For PR review (alex / review agent), start at [docs/engineering/review-changelog.md](docs/engineering/review-changelog.md) and validate each `RCxx` / `NCxx` / `FUxx`. Do not invent scope.

**Stability first:** do not restore Stores/catalog/price UI / rich product forms unless the PR explicitly takes that scope. Core path is SIWA → one living cart → name-only add → Completed → overnight History by day → invite from Аккаунт — see [docs/requirements/product.md](docs/requirements/product.md).

## Config

Source of truth: [`Tooling/runtime.yml`](Tooling/runtime.yml)

Style (app-owned): `Tooling/.swiftlint.yml`, `Tooling/.swiftformat` — see [`Tooling/docs/style-config.md`](Tooling/docs/style-config.md).

```yaml
scheme: OneCart
project: OneCart/OneCart.xcodeproj
```

## Versioning

- Marketing versions use `MAJOR.MINOR.PATCH`, with all three components treated as integers.
- A feature release increments MINOR and resets PATCH to `0`; a fix-only release with no new features increments PATCH instead. Do not roll MAJOR without an explicit request.
- The build number is separate: reset it to `1` for a new marketing version, then increment within that version.
- Keep the app and widget extension versions and build numbers aligned in Debug and Release.

## Modules

| Path | Role |
|------|------|
| `OneCart/Application/` | Composition root (`AppSession`, `CartSyncService`, `FamilyShareOrchestrator`) |
| `OneCart/Features/` | Feature Views + ViewModels (`Shopping/`, `Account/`, `Onboarding/`) |
| `OneCart/Data/` | Persistence, CloudKit, Auth |
| `OneCart/Shared/` | Cross-feature helpers |
| `OneCart/Resources/` | Bundle resources |
| `OneCart/Tests/` | Unit tests (`OneCartTests` target) |
| `docs/` | See [docs/README.md](docs/README.md) |
| `assets/` | Brand / store masters (not in the app bundle) |
| `Tooling/` | Engineering Runtime — see [Tooling/README.md](Tooling/README.md) |
| `justfile` | App-owned shim that imports `Tooling/justfile` (+ `demo` recipe) |
| `scripts/install-hooks.sh` | Installs the repository pre-push hook |

## Definition of Done

```bash
just verify
```

## Commands

```bash
brew bundle --file=Tooling/Brewfile
just doctor
just diagnose
just build
just test
just verify
just run-sim
just demo role=owner
just demo-tab role=member tab=cart
```

Install repository hooks once with `./scripts/install-hooks.sh`. The pre-push hook
runs smoke tests for branch updates and skips tag-only pushes and ref deletions.
