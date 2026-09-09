# OneCart — agent notes (thin)

Project facts only. Agent behavior lives in the Cursor Brain (`agents-kit`).

## Project

- Name: OneCart
- Supported devices: iPhone only (`TARGETED_DEVICE_FAMILY = 1`); keep app, widget, and test targets aligned.
- Context: see `.cursor/project-context` (`personal`)
- Open: `OneCart/OneCart.xcodeproj`
- Runtime: `Tooling/` (ios-engineering-runtime 0.2.2)
- Docs index: [docs/README.md](docs/README.md)

## Review

For PR review (alex / review agent), start at [docs/review-changelog.md](docs/review-changelog.md) and validate each `RCxx` / `NCxx` / `FUxx`. Do not invent scope.

**Stability first:** do not restore Stores/catalog/price UI / rich product forms unless the PR explicitly takes that scope. Core path is SIWA → one living cart → name-only add → Completed → overnight History by day → invite from Аккаунт — see [docs/product.md](docs/product.md).

## Config

Source of truth: [`Tooling/runtime.yml`](Tooling/runtime.yml)

Style (app-owned): `Tooling/.swiftlint.yml`, `Tooling/.swiftformat` — see [`Tooling/docs/style-config.md`](Tooling/docs/style-config.md).

```yaml
scheme: OneCart
project: OneCart/OneCart.xcodeproj
```

## Versioning

- Marketing versions use `MAJOR.MINOR`, with both components treated as integers: `2.4 → 2.5 → … → 2.9 → 2.10`.
- Increment MINOR for the next release; do not roll MAJOR at 9 and never add a third component.
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
