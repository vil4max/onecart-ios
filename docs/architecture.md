# Architecture (Level 1 MVVM)

## Ladder decision

- **Level 1 — MVVM + POP services**
- **No Coordinator** — Welcome → tabs + sheets; share URL handled at app root
- **No Clean Domain / UseCase modules** — repositories and CloudKit/Auth services are enough

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
| `OneCart/Application/AppSession.swift` | Launch, selected family, sync state, CloudKit events |
| `OneCart/Application/AppDelegate.swift` | System CloudKit share invitation handoff |
| `OneCart/Application/RootView.swift` | Launch → welcome or main tabs |
| `OneCart/Data/Persistence/PersistenceController.swift` | Private/shared SQLite + CloudKit scopes |
| `OneCart/Data/Persistence/FamilySpaceRepository.swift` | Local CRUD + shared-record permission checks |
| `OneCart/Data/CloudKit/CloudKitServices.swift` | iCloud account, `CKShare` roles, invites, members |
| `OneCart/Data/Authentication/AppleSignInService.swift` | Sign in with Apple + Keychain session |
| `OneCart/Features/Onboarding/WelcomeView.swift` | SIWA + iCloud connect |
| `OneCart/Features/Settings/SettingsView.swift` | Members, system share link, family management |

## Stores and sync

Same SQLite filenames as older installs (no rename):

| File | CloudKit scope |
|------|----------------|
| `OneCart-private.sqlite` | private database |
| `OneCart-shared.sqlite` | shared database |

New household spaces and children go to the private store. After `CKShare` accept, the shared space appears in the shared store. Local saves are immediate; CloudKit syncs when online.

`CKShare` uses `publicPermission = .none`. See [product.md](product.md) for Household vs Apple Family positioning.

Container: `iCloud.com.vil555tim.onecart`. Record types (`OneCartCoreDataV4`): `FamilySpace`, `Store`, `ShoppingList`, `Product`, `PurchaseHistory`, `HistoryItem`, plus system `CKShare` on root `FamilySpace`.

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
