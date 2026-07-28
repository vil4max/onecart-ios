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
| Invite + Delete cart from Аккаунт; members on the same screen | Multi-cart switcher |
| Hard cart sync (pull / appear / foreground) with nav «Updating…» | Toast / sync banner chrome |
| System alert for errors | — |

Store/catalog **UI modules are removed from the target**. Core Data still models `Store` and price fields for the CloudKit sync graph and older local rows. Do not re-wire catalog/store/price screens until two-device invite/sync is solid.

## Composition root

`AppSession` (typealias `AppModel` for gradual View migration) owns published session state and thin wrappers for Views. Heavy work is delegated:

| Type | Role |
|------|------|
| `SessionBootstrapper` | SIWA restore / welcome retry; Core Data wipe only on typed store failure |
| `CartContentStore` | lists / products / history pages; reload after viewContext reset |
| `CartSyncService` | `syncCart(reason:) → CartSyncOutcome`, viewContext reset/refetch, `contentRevision`, `isCartSyncing` |
| `CloudSyncCoordinator` | CloudKit observers, connectivity, scheduled reload, maps sync outcome → `syncState` / alerts |
| `ProfileStore` | device-local avatar/banner via `ProfileMediaStore` (not CloudKit) |
| `FamilyShareOrchestrator` | invite link creation, owner ACL heal, delete cart + recreate |
| `FamilySpaceRepository` | local CRUD / purchase sessions |
| `CloudKitBackendService` + `FamilyInviteLinkBuilder` | iCloud account, members, share lifecycle |

Feature screens bind to `AppSession` / feature ViewModels. Views stay thin.

## Owner files

| Path | Role |
|------|------|
| `OneCart/Application/AppSession.swift` | Composition root: published session + View wrappers |
| `OneCart/Application/SessionBootstrapper.swift` | Welcome / prepare / explicit wipe gate |
| `OneCart/Application/CartContentStore.swift` | Cart content + history page size 30 / loadMore |
| `OneCart/Application/CartSyncService.swift` | Hard cart refresh / sync chrome state |
| `OneCart/Application/CloudSyncCoordinator.swift` | Observers, connectivity, sync outcome application |
| `OneCart/Application/ProfileStore.swift` | Device-local profile media |
| `OneCart/Application/FamilyShareOrchestrator.swift` | Invite / ACL heal / delete-and-recreate |
| `OneCart/Application/AppDelegate.swift` | Scene config + fallback CloudKit share handoff |
| `OneCart/Application/SceneDelegate.swift` | Scene-based `CKShare` accept + cold-start metadata |
| `OneCart/Application/RootView.swift` | Launch → welcome or main tabs; system alert |
| `OneCart/Application/MainTabView.swift` | Корзина / История / Аккаунт |
| `OneCart/Data/Persistence/PersistenceController.swift` | Private/shared SQLite + CloudKit scopes; non-destructive `load()` |
| `OneCart/Data/Persistence/FamilySpaceRepository.swift` | Local CRUD; `completePurchased` (checked items → session) |
| `OneCart/Data/CloudKit/` | Split: models, errors, share ACL/branding, permissions, backend, invite builder |
| `OneCart/Data/Authentication/AppleSignInService.swift` | Sign in with Apple + Keychain session |
| `OneCart/Features/Onboarding/WelcomeView.swift` | SIWA + trolley metaphor + iCloud connect |
| `OneCart/Features/Shopping/ShoppingViews.swift` | Cart home, list, toggle, quick add, nav sync title |
| `OneCart/Features/Shopping/HistoryViews.swift` | History list + detail (`historyHasMore` / load more) |
| `OneCart/Features/Shopping/CartChromeViews.swift` | Empty / read-only / unavailable chrome |
| `OneCart/Features/Settings/MoreView.swift` | Account: members / invite / delete cart / sign out |
| `OneCart/Features/Settings/CartManagementSheet.swift` | Members / leave cart (sheet helpers) |

## Trade-offs (recovery / sync)

| Choice | Why |
|--------|-----|
| `load()` never auto-wipes | Offline SQLite must survive transient open failures; wipe only from welcome retry after Core Data failure + diagnostics copy |
| `CartSyncOutcome` + failed ≠ synchronized | UI must not show “ok” after hard-refresh throws |
| History page size 30 + offset fetch | Avoid loading full purchase history into memory; UI “show more” calls `loadMoreHistory` |
| Profile media device-local | Photos stay off CloudKit; shopping data syncs separately |
| NC09: no pre-merge GitHub Actions | Xcode Cloud release-only for this personal train |

## Fragile-test matrix (living checklist)

| ID | Invariant | Tests |
|----|-----------|-------|
| F1 | Failed `load()` does not destroy store files | `FragileStoreLoadTests.testLoadFailureDoesNotDestroyStoreFiles` |
| F2 | Explicit wipe only on Core Data welcome failure | `testIsUserFacingCoreDataFailureIgnoresCloudKit`, `testRetryWelcomeDoesNotWipeUnlessCoreDataFailure`, `testShouldHardResetStoresOnlyForCoreDataWelcomeFailure` |
| F3 | Diagnostics snapshot before explicit hard reset | `testDiagnosticsSnapshotCreatedBeforeExplicitHardReset` |
| F4 | Sync failure → `.failed`, not fake synchronized | `FragileSyncOutcomeTests.testSyncCartPullFailureSetsFailedState` (+ appear no alert) |
| F5 | After `viewContext.reset`, products republish | `SharedCartJoinTests.testRefreshFromServerPicksUpToggledPurchasedState`, `testCartContentStorePublishesAfterReload` |
| F6 | Shared join/adopt order | `SharedCartJoinTests` (hard gate) |
| F7 | Permission deny ≠ sync fail message | Fragile sync + `CartAccessTests` selective permission |
| F8 | CartContentStore publish after reload | `testCartContentStorePublishesAfterReload` |
| F9 | History default page 30 + loadMore appends | `HistoryPaginationTests` |
| F10 | New Application files in Sources | Stage DoD via `test_sim` compile |

## Purchase completion

`completePurchased(listID:)` soft-deletes **checked** products into a `PurchaseHistory` session and leaves the active list in place. Unchecked items stay. The cart list is never marked `.completed` and never replaced.

## Stores and sync

Same SQLite filenames as older installs (no rename):

| File | CloudKit scope |
|------|----------------|
| `OneCart-private.sqlite` | private database |
| `OneCart-shared.sqlite` | shared database |

New household spaces and children go to the private store. After `CKShare` accept, the shared space appears in the shared store. Local saves are immediate; CloudKit syncs when online.

There is **no public API to force** a CloudKit import/export mirror ([TN3163](https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer) / [TN3164](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer)). The app schedules best-effort hard refresh after import events, pull-to-refresh, cart appear, and foreground. ViewContext uses `NSMergeByPropertyStoreTrumpMergePolicy` so remote store wins over stale in-memory values. User-facing failures use a system alert; transient share create retries honor `CKError.retryAfterSeconds` when present.

`CKShare` uses `publicPermission = .readWrite` (link-join). Owner **Delete cart** stops the share (old URL dies) and creates a fresh private cart. See [product.md](product.md) and [privacy.md](privacy.md).

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
