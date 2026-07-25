# OneCart — agent notes (thin)

Project facts only. Agent behavior lives in the Cursor Brain (`cursor-agent-kit`).

## Project

- Name: OneCart
- Context: see `.cursor/project-context` (`personal`)
- Open: `OneCart/OneCart.xcodeproj`
- Docs index: [docs/README.md](docs/README.md)

## Review

For PR review (alex / review agent), start at [docs/review-changelog.md](docs/review-changelog.md) and validate each `RCxx` / `NCxx` / `FUxx`. Do not invent scope.

## Config

Source of truth: [`Tooling/runtime.yml`](Tooling/runtime.yml)

```yaml
scheme: OneCart
project: OneCart/OneCart.xcodeproj
```

## Modules

| Path | Role |
|------|------|
| `OneCart/Application/` | Composition root (`AppSession`), app entry |
| `OneCart/Features/` | Feature Views + ViewModels |
| `OneCart/Data/` | Persistence, CloudKit, Auth, Migration |
| `OneCart/Shared/` | Cross-feature helpers |
| `OneCart/Resources/` | Bundle resources |
| `OneCart/Tests/` | Unit tests (`OneCartTests` target) |
| `docs/` | See [docs/README.md](docs/README.md) |
| `assets/` | Brand / store masters (not in the app bundle) |
| `Tooling/` | Engineering Runtime — see [Tooling/README.md](Tooling/README.md) |
| `justfile` | Thin shim that imports `Tooling/justfile` |

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
```
