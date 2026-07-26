# Architecture (Level 1 MVVM)

## Ladder decision

- **Level 1 — MVVM + POP services**
- **No Coordinator** — Welcome → tabs + sheets; share URL handled at app root
- **No Clean Domain / UseCase modules** — repositories and CloudKit/Auth services are enough

## Stability-first shell

Product policy (see [product.md](product.md)): **stabilize the household cart + CKShare path before re-adding features.**

| In the shell now | Intentionally out of navigation |
|------------------|----------------------------------|
| Cart (one list, quick name add, invite) | Stores tab / store-first shopping |
| Settings (profile, family sheet, history sheet) | Catalog browser as primary add path |
| System alert for errors | Toast / sync banner chrome |

Legacy store/catalog code may still compile in the target so we avoid risky mass deletes of CloudKit-related types mid-release. New work should not wire those surfaces back into `MainTabView` or the cart FAB until two-device invite/sync is solid.

## Composition root

`AppSession` (typealias `AppModel` for gradual View migration) owns:

- Sign in with Apple session restore
- iCloud readiness / sync state
- Selected Household cart
- CloudKit share accept / invite orchestration
- Factory-style access to `FamilySpaceRepository` and CloudKit/Auth services

Feature screens bind to `AppSession` / feature ViewModels. Views stay thin.

## Owner files

| Path | Role |
|------|------|
| `OneCart/Application/AppSession.swift` | Launch, selected family, sync state, CloudKit events, `alertMessage` |
| `OneCart/Application/AppDelegate.swift` | System CloudKit share invitation handoff |
| `OneCart/Application/RootView.swift` | Launch → welcome or main tabs; system alert for errors |
| `OneCart/Data/Persistence/PersistenceController.swift` | Private/shared SQLite + CloudKit scopes |
| `OneCart/Data/Persistence/FamilySpaceRepository.swift` | Local CRUD + shared-record permission checks |
| `OneCart/Data/CloudKit/CloudKitServices.swift` | iCloud account, `CKShare` roles, invites, members |
| `OneCart/Data/Authentication/AppleSignInService.swift` | Sign in with Apple + Keychain session |
| `OneCart/Features/Onboarding/WelcomeView.swift` | SIWA + iCloud connect |
| `OneCart/Features/Settings/SettingsView.swift` | Account, history sheet, family invite sheet |
| Main tabs | Cart + Settings only (Stores tab removed from shell) |

## Stores and sync

Same SQLite filenames as older installs (no rename):

| File | CloudKit scope |
|------|----------------|
| `OneCart-private.sqlite` | private database |
| `OneCart-shared.sqlite` | shared database |

New household spaces and children go to the private store. After `CKShare` accept, the shared space appears in the shared store. Local saves are immediate; CloudKit syncs when online. `AppSession.syncState` tracks sync internally; user-facing failures use a system alert (no sync banner/toast).

`CKShare` uses `publicPermission = .none`. See [product.md](product.md) for Household vs Apple Family positioning.

Container: `iCloud.com.vil555tim.onecart`. Record types (`OneCartCoreDataV6`): `FamilySpace`, `Store`, `ShoppingList`, `Product`, `PurchaseHistory`, `HistoryItem`, plus system `CKShare` on root `FamilySpace`. No Core Data uniqueness constraints (CloudKit-incompatible); duplicates are soft-deleted via launch dedupe.

## Folder layout

```text
.
├── OneCart/          # Xcode product (Application, Features, Data, Shared, Resources, Tests)
├── docs/             # this set
├── assets/           # brand / store masters (not in app bundle)
├── Tooling/          # Engineering Runtime — see Tooling/README.md
└── justfile          # import Tooling/justfile
```

Full tree and commands: [README.md](../README.md).
