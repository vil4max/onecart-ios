# OneCart architecture (Level 1 MVVM)

## Ladder decision

- **Level 1 — MVVM + POP services** (this PR)
- **No Coordinator** — Welcome → tabs + sheets; share URL handled at app root
- **No Clean Domain / UseCase modules** — repositories and CloudKit/Auth services are enough

## Composition root

`AppSession` (typealias `AppModel` for gradual View migration) owns:

- Sign in with Apple session restore
- iCloud readiness / sync state
- Selected Household cart
- CloudKit share accept / invite orchestration
- Factory-style access to `FamilySpaceRepository` and CloudKit/Auth services

Feature screens bind to `AppSession` / future feature ViewModels. Views should stay thin.

## Folder layout

```text
OneCart/                    # Xcode product directory
  OneCart.xcodeproj
  Application/
  Features/
  Data/
  Shared/
  Resources/
  Tests/
Tooling/                    # Engineering Runtime (host build adapters)
docs/
assets/
```

## Platform sync

CloudKit + `NSPersistentCloudKitContainer` + `CKShare` with `publicPermission = .none`.

See [product-flow-v1.1.md](product-flow-v1.1.md) for Household / Apple Family positioning.
