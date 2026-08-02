# OneCart — agent notes (thin)

Project facts only. Agent behavior lives in the Cursor Brain (`agents-kit`).

## Project

- Name: OneCart
- Context: see `.cursor/project-context` (`personal`)
- Open: `OneCart/OneCart.xcodeproj`
- Runtime: `Tooling/` (ios-agent-harness 0.2.2)
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

## Modules

| Path | Role |
|------|------|
| `OneCart/Application/` | Composition root (`AppSession`, `CartSyncService`, `FamilyShareOrchestrator`) |
| `OneCart/Features/` | Feature Views + ViewModels |
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
