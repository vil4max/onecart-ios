# Architecture (Level 1 MVVM)

## Ladder decision

- **Level 1 — MVVM + POP services**
- **No Coordinator** — Welcome → tab shell; share URL handled at app root
- **No Clean Domain / UseCase modules** — repositories and CloudKit/Auth services are enough

## Product shell

Product policy (see [product.md](product.md)): **one living family cart + CKShare path first.**

| In the shell now | Intentionally out of navigation |
|------------------|----------------------------------|
| Tabs: Корзина / История / Аккаунт | Theme-unit prefs / Stores / catalog UI |
| Name-only quick add (medium sheet) | Rich product editor / money UI |
| Invite from Аккаунт; members on the same screen | Multi-cart switcher |
| System alert for errors | Toast / sync banner chrome |

Store/catalog **UI modules are removed from the target**. Core Data still models `Store` and price fields for the CloudKit sync graph and legacy data. Do not re-wire catalog/store/price screens until two-device invite/sync is solid.

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
| `OneCart/Application/AppSession.swift` | Launch, selected family, sync state, CloudKit events, `alertMessage`, `cartTitle` |
| `OneCart/Application/AppDelegate.swift` | System CloudKit share invitation handoff |
| `OneCart/Application/RootView.swift` | Launch → welcome or main tabs; members sheet; system alert |
| `OneCart/Application/MainTabView.swift` | Корзина / История / Аккаунт |
| `OneCart/Data/Persistence/PersistenceController.swift` | Private/shared SQLite + CloudKit scopes |
| `OneCart/Data/Persistence/FamilySpaceRepository.swift` | Local CRUD; `completePurchased` (checked items → session) |
| `OneCart/Data/CloudKit/CloudKitServices.swift` | iCloud account, `CKShare` roles, invites, members |
| `OneCart/Data/Authentication/AppleSignInService.swift` | Sign in with Apple + Keychain session |
| `OneCart/Features/Onboarding/WelcomeView.swift` | SIWA + trolley metaphor + iCloud connect |
| `OneCart/Features/Shopping/ShoppingViews.swift` | Cart UI, quick add, history sessions |
| `OneCart/Features/Settings/MoreView.swift` | Profile / members / invite / sign out |
| `OneCart/Features/Settings/CartManagementSheet.swift` | Members / leave cart |

## Purchase completion

`completePurchased(listID:)` soft-deletes **checked** products into a `PurchaseHistory` session and leaves the active list in place. Unchecked items stay. The cart list is never marked `.completed` and never replaced.

## Stores and sync

Same SQLite filenames as older installs (no rename):

| File | CloudKit scope |
|------|----------------|
| `OneCart-private.sqlite` | private database |
| `OneCart-shared.sqlite` | shared database |

New household spaces and children go to the private store. After `CKShare` accept, the shared space appears in the shared store. Local saves are immediate; CloudKit syncs when online. User-facing failures use a system alert (no sync banner/toast).

`CKShare` uses `publicPermission = .none`. See [product.md](product.md) for Household vs Apple Family positioning.

Container: `iCloud.com.vil555tim.onecart`. Record types (`OneCartCoreDataV6`): `FamilySpace`, `Store`, `ShoppingList`, `Product`, `PurchaseHistory`, `HistoryItem`, plus system `CKShare` on root `FamilySpace`. No Core Data uniqueness constraints (CloudKit-incompatible); duplicates are soft-deleted via launch dedupe.

## Folder layout

```text
.
├── OneCart/          # Xcode product (Application, Features, Data, Shared, Resources, Tests)
├── docs/             # this set
├── assets/           # brand / store masters (not in app bundle)
├── Tooling/          # Engineering Runtime — see Tooling/justfile
└── justfile          # import Tooling/justfile
```

Full tree and commands: [README.md](../README.md).
