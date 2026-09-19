# OneCart — agent notes (thin)

<!-- repository-visibility-policy -->
Repository visibility: **PUBLIC**.

## Data handling

Never include confidential or sensitive personal data in source, documentation,
Git history, commit messages, issues, pull requests, logs, or artifacts. This
includes private financial information, compensation expectations or offers,
personal assessments, health or family details, private correspondence, and
application records. Use fictional data in examples and tests. Never commit
credentials, tokens, passwords, session data, or private keys.

## Documentation quality

Write public-facing documentation in clear, technical English for readers
without access to private workspace context. Keep instructions accurate,
repository-relative, and reproducible. Distinguish implemented behavior from
plans, state relevant prerequisites and limitations, and update documentation
with the behavior it describes. Exclude personal notes, internal handoffs,
machine-specific paths, and unsupported claims.
<!-- /repository-visibility-policy -->

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

For PR review (owner / review agent), start at [docs/engineering/review-changelog.md](docs/engineering/review-changelog.md) and validate each `RCxx` / `NCxx` / `FUxx`. Do not invent scope.

**Stability first:** do not restore Stores/catalog/price UI / rich product forms unless the PR explicitly takes that scope. Core path is SIWA → one living cart → name-only add → Completed → overnight History by day → invite from Настройки — see [docs/requirements/product.md](docs/requirements/product.md).

## CI and releases

Source: [ADR 0003](docs/decisions/0003-ci-split.md). GitHub Actions tests; Xcode Cloud only archives.

- `main` — development. `Tests` (`.github/workflows/tests.yml`) runs on every push and PR.
- `testflight` and `release` are moved only by GitHub Actions, only by fast-forward. Never push,
  force-push, reset, or delete them.
- Version tags `vMAJOR.MINOR.PATCH` are created and pushed only by the owner; an agent does not tag.
- Branches and worktrees exist only while work is in progress: delete merged branches locally and on
  GitHub right away. Permanent branches are `main`, `testflight`, `release`. No leftover build
  artifacts in the working tree.
- Xcode Cloud workflow settings live in App Store Connect, not in the repo; change them only with
  the owner's explicit approval and update ADR 0003 in the same change.

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
