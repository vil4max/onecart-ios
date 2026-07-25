# OneCart — agent notes (thin)

Project facts only. Agent behavior lives in the Cursor Brain (`cursor-agent-kit`).

## Project

- Name: OneCart
- Context: see `.cursor/project-context` (`personal`)
- Open: `OneCart/OneCart.xcodeproj`
- See [README.md](README.md), [NATIVE_IOS.md](NATIVE_IOS.md), [docs/architecture.md](docs/architecture.md), [docs/product-flow-v1.1.md](docs/product-flow-v1.1.md)

## Review

For PR review (alex / review agent), start at [docs/review-changelog.md](docs/review-changelog.md) and validate each `RCxx` / `NCxx` / `FUxx`. Do not invent scope.

## Config

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
| `Tooling/` | Engineering Runtime (host build adapters — not CloudKit) |

## Definition of Done

```bash
just verify
```

## Commands

```bash
just doctor
just diagnose
just build
just test
```
