# Architecture (Level 1 MVVM)

## Ladder decision

- **Level 1 — MVVM + POP services**
- **No Coordinator** — Welcome → tab shell; share URL handled at app root
- **No Clean Domain / UseCase modules** — repositories and CloudKit/Auth services are enough

## Product shell

Product policy (see [product.md](../requirements/product.md)): **one living family cart + CKShare path first.**

| In the shell now | Intentionally out of navigation |
|------------------|----------------------------------|
| Tabs: Корзина / История / Настройки; appearance, icon and language preferences | Unit / price input / Stores / catalog UI |
| Name-only inline add via `+` empty row + keyboard; category SF Symbol from keywords, optional on-device FM refine | Rich product editor / money UI |
| Invite + Revoke invite + leave from Настройки; members on the same screen | Multi-cart switcher (FU01) |
| Hard cart sync (pull / appear / foreground) with nav «Updating…» | Toast / sync banner chrome |
| System alert for errors | — |

Store/catalog **UI modules are removed from the target**. Core Data still models `Store` and price fields for the CloudKit sync graph and older local rows. Do not re-wire catalog/store/price screens until two-device invite/sync is solid.

## Composition root

`AppSession` is a `@MainActor @Observable` root that owns the session state and thin wrappers;
SwiftUI tracks its properties and those of its `@Observable` collaborators directly (no
`ObservableObject`, Combine bridges or `objectWillChange` since 2026-09-22). Heavy work is delegated:

| Type | Role |
|------|------|
| `SessionBootstrapper` | SIWA restore / welcome retry; preserves pending account-deletion recovery |
| `CartContentStore` | lists / products / history pages; reload after viewContext reset |
| `CartSyncService` | `syncCart(reason:) → CartSyncOutcome`, viewContext reset/refetch, `contentRevision`, `isCartSyncing` |
| `CloudSyncCoordinator` | CloudKit observers, scheduled reload, maps sync outcome → `syncState` / alerts |
| `ConnectivityMonitor` | `NWPathMonitor` online/offline callbacks for the coordinator |
| `HouseholdCartCoordinator` | Ensure/adopt household cart + invitee shared-gone fallback |
| `InviteLinkPreparer` | Invite link cache / warm-up (silent soft-fail) |
| `FamilyShareOrchestrator` | invite link creation; owner ACL heal (does not reopen a revoked invite door); revoke invite (close door) |
| `FamilySpaceRepository` | local CRUD / purchase sessions (+ merge / dedupe / product slices) |
| `CloudKitBackendService` + `FamilyInviteLinkBuilder` | iCloud account, members, share lifecycle, private-zone account deletion |

Screens never see `AppSession`. Its surface is split into role protocols in
`OneCart/Application/Services/` (`SessionStateReading`, `CartEditing`, `HistoryBrowsing`,
`MembershipManaging`, `AccountManaging`, `WelcomeSigningIn`, `HouseholdCartBootstrapping`,
`AlertPresenting`, `MainTabRouting`), declared on the session in `AppSession+Services.swift`.
Each screen has a `@MainActor @Observable` ViewModel that takes those protocols in `init`
(`CartViewModel`, `HistoryViewModel`, `AccountViewModel`, `WelcomeViewModel`); the screen
boundary (`RootSessionView` for Welcome, `MainTabView` for the tabs) creates the ViewModels once
as `@State` from the session and passes them into the screens. Tests drive the ViewModels through
fakes that conform to the same protocols (`OneCart/Tests/Support/Fake*.swift`); hosted-view tests
mount the screens over those fakes.

God-file split train (RC31): composition root target ~200 lines; hard trigger 400+. `AppSession` stays a thin root; behavior lives in `AppSession+*.swift` extensions and the coordinators above.

## Owner files

| Path | Role |
|------|------|
| `OneCart/Application/AppSession.swift` | Composition root: observable session state + wiring |
| `OneCart/Application/Services/*.swift`, `AppSession+Services.swift` | Role protocols the screens depend on, and the session's conformances |
| `OneCart/Features/*/…ViewModel.swift` | Per-screen `@Observable` ViewModels over the role protocols |
| `OneCart/Application/AppSession+*.swift` | Welcome/auth, hosts, cart mutations, membership, family selection |
| `OneCart/Application/SessionTypes.swift` | Shared session enums / device preferences types |
| `OneCart/Application/SessionBootstrapper.swift` | Welcome / prepare / explicit wipe gate |
| `OneCart/Application/CartContentStore.swift` | Cart content + history page size 30 / loadMore |
| `OneCart/Application/CartSyncService.swift` | Hard cart refresh / sync chrome state |
| `OneCart/Application/CloudSyncCoordinator.swift` | Observers, scheduled reload, sync outcome application |
| `OneCart/Application/ConnectivityMonitor.swift` | Path monitor used by cloud sync |
| `OneCart/Application/HouseholdCartCoordinator.swift` | Household ensure / adopt / shared-gone |
| `OneCart/Application/InviteLinkPreparer.swift` | Invite link prepare / cache |
| `OneCart/Application/FamilyShareOrchestrator.swift` | Invite / ACL heal / revoke without replacing the cart |
| `OneCart/Application/AppDelegate.swift` | Scene config + fallback CloudKit share handoff |
| `OneCart/Application/SceneDelegate.swift` | Scene-based `CKShare` accept + cold-start metadata |
| `OneCart/Application/RootView.swift` | Launch → welcome or main tabs; system alert |
| `OneCart/Application/LaunchChrome.swift` | Launch cart ride + shared chrome controls |
| `OneCart/Application/MainTabView.swift` | Корзина / История / Настройки |
| `OneCart/Data/Persistence/PersistenceController.swift` | Private/shared SQLite + CloudKit scopes; non-destructive `load()` |
| `OneCart/Data/Persistence/PersistenceController+*.swift` | Store descriptions + diagnostics / wipe / env reconcile |
| `OneCart/Data/Persistence/OneCartManagedObjectModel.swift` | Programmatic `NSManagedObjectModel` |
| `OneCart/Data/Persistence/ManagedObjects.swift` | Core Data entity subclasses |
| `OneCart/Data/Persistence/FamilySpaceRepository.swift` | Local CRUD; `archivePurchasedBefore` / `completePurchased` (Completed → history) |
| `OneCart/Data/Persistence/FamilySpaceRepository+*.swift` | Merge / dedupe / product mutation slices |
| `OneCart/Data/CloudKit/` | Split: models, errors, share ACL/branding, permissions, backend, invite builder |
| `OneCart/Data/Authentication/AppleSignInService.swift` | Sign in with Apple + Keychain session |
| `OneCart/Features/Onboarding/WelcomeView.swift` | SIWA + cart pitch + iCloud connect |
| `OneCart/Features/Shopping/HomeView.swift` | Cart home |
| `OneCart/Features/Shopping/ShoppingListView.swift` | Active list composition + inline add/edit; To Buy / Completed |
| `OneCart/Features/Shopping/CartProductRow.swift` | Product row, purchase toggle, category thumbnail |
| `OneCart/Features/Shopping/CartAddFAB.swift` | FAB `+` |
| `OneCart/Features/Shopping/HistoryViews.swift` | History by day (`historyHasMore` / load more); read-only |
| `OneCart/Features/Shopping/HistoryDetailViews.swift` | Day detail product list |
| `OneCart/Features/Shopping/CartChromeViews.swift` | Empty / read-only / unavailable chrome |
| `OneCart/Shared/Support/ProductCategory.swift` | Metro categories, inference, section grouping |
| `OneCart/Shared/Support/CategoryClassifier.swift` | Keyword + on-device FM category refine |
| `OneCart/Features/Account/AccountView.swift` | Account tab shell |
| `OneCart/Features/Account/AccountViewModel.swift` | Share / leave / revoke / rename / display-name / icon presentation state |
| `OneCart/Features/Account/AccountRows.swift` | Member and action rows |
| `OneCart/Features/Account/CartShareActivityBridge.swift` | Share sheet activity items / metadata |
| `Tooling/` | Engineering Runtime 0.2+ (`backend/`, app-owned style configs) |

## Trade-offs (recovery / sync)

| Choice | Why |
|--------|-----|
| `load()` preserves stores on transient failures | Explicit welcome recovery requires a store-load failure (`WelcomeFailureCause.storeLoad`, armed only by `persistence.load()` and consumed by one Retry) and a diagnostics copy; errors from later bootstrap steps never arm the wipe, because they can come from unsynced local edits; a confirmed account-deletion marker finishes previously authorized cleanup before reopening |
| `CartSyncOutcome` + failed ≠ synchronized | Coalesced callers receive the final queued refresh outcome; recovery mode keeps `.failed` |
| History page size 30 + offset fetch | Avoid loading full purchase history into memory; UI “show more” calls `loadMoreHistory` |
| Device-local profile | Display name and local avatar/banner preferences are separate from CloudKit membership |
| CI split ([ADR 0003](../decisions/0003-ci-split.md), supersedes NC09; [ADR 0004](../decisions/0004-tag-gated-testflight.md)) | GitHub Actions runs tests on push/PR; an annotated `tf-` tag fast-forwards `testflight`; Xcode Cloud only archives from `testflight` |

## Fragile-test matrix (living checklist)

| ID | Invariant | Tests |
|----|-----------|-------|
| F1 | Failed `load()` does not destroy store files | `FragileStoreLoadTests.test_REQ_AUTH_080_loadFailureDoesNotDestroyStoreFiles` |
| F2 | Explicit wipe only when `persistence.load()` itself failed with a store-load Cocoa code; classified by error code, never by localized text | `test_REQ_AUTH_010_isUserFacingCoreDataFailureIgnoresCloudKit`, `test_REQ_AUTH_010_retryWelcomeDoesNotWipeUnlessCoreDataFailure`, `test_REQ_AUTH_010_shouldHardResetStoresOnlyForCoreDataWelcomeFailure`, `test_REQ_AUTH_010_wrappedLoadFailureWithNonEnglishDescriptionIsStoreLoadFailure`, `test_REQ_AUTH_010_postLoadCocoaSaveErrorDoesNotArmHardReset`, `test_REQ_AUTH_010_failureCauseArmsOnlyForStoreLoadCodes`, `test_REQ_AUTH_010_storeLoadFailureArmsHardResetAndRetryRecovers` |
| F3 | Diagnostics snapshot before explicit hard reset | `test_REQ_AUTH_080_diagnosticsSnapshotCreatedBeforeExplicitHardReset` |
| F4 | Sync failure → `.failed`, not fake synchronized | `FragileSyncOutcomeTests.test_REQ_SYNC_010_syncCartPullFailureSetsFailedState` (+ appear no alert) |
| F5 | After `viewContext.reset`, products republish | `SharedCartJoinTests.test_REQ_SYNC_030_refreshFromServerPicksUpToggledPurchasedState`, `test_REQ_SYNC_010_cartContentStorePublishesAfterReload` |
| F6 | Shared join/adopt order | `SharedCartJoinTests` (hard gate) |
| F7 | Permission deny ≠ sync fail message | Fragile sync + `CartAccessTests` selective permission |
| F8 | CartContentStore publish after reload | `test_REQ_SYNC_010_cartContentStorePublishesAfterReload` |
| F9 | History default page 30 + loadMore appends | `HistoryPaginationTests` |
| F10 | New Application files in Sources | Stage DoD via `test_sim` compile |
| F11 | A partial store-load failure detaches the stores that did load (files stay on disk, F1), so `load()` can be retried in the same process instead of failing with Cocoa 134081 ("can't add the same store twice") | `FragileStoreLoadTests.test_REQ_AUTH_080_partialLoadFailureAllowsRetryInSameProcess` |

## Purchase completion / History

Checked items stay on the living cart under **Completed**. There is no manual finish-shopping action in the UI. History is **read-only** (no delete day / delete entry in the UI).

On cart sync (`.appear` / `.foreground`), `archivePurchasedBefore` moves products with `isPurchased` and `purchasedAt` before the start of today into `PurchaseHistory` / `HistoryItem` (soft-delete from the list). Today’s Completed items stay. History UI groups items by purchase day (`purchasedAt`).

`completePurchased(listID:)` remains for demo/tests (archives all currently checked items at once). The cart list is never marked `.completed` and never replaced.

## Stores and sync

Same SQLite filenames as older installs (no rename):

| File | CloudKit scope |
|------|----------------|
| `OneCart-private.sqlite` | private database |
| `OneCart-shared.sqlite` | shared database |

DEBUG demo mode (`-oneCartDemoUI`) opens the same filenames under `Application Support/OneCartDemo/<role>/` and keeps its Sign in with Apple credential in memory, so seeded demo rows never reach the real stores, CloudKit, or the Keychain.

New household spaces and children go to the private store. After `CKShare` accept, the shared space appears in the shared store. Local saves are immediate; CloudKit syncs when online.

There is **no public API to force** a CloudKit import/export mirror ([TN3163](https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer) / [TN3164](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer)). The app schedules best-effort hard refresh after import events, pull-to-refresh, cart appear, and foreground. ViewContext uses `NSMergeByPropertyStoreTrumpMergePolicy` so remote store wins over stale in-memory values. User-facing failures use a system alert; transient share create retries honor `CKError.retryAfterSeconds` when present.

`CKShare` uses `publicPermission = .readWrite` (link-join). Owner **Revoke invite** sets `publicPermission = .none` (no new joins; members stay; same `FamilySpace` UUID). Owner ACL heal upgrades participant write ACL but must not reopen a revoked public door; **Share** / invite create reopens with `reopenInviteDoor`. After Accept, reload always prefers a shared `FamilySpace` and hides personal from the session list; personal stays on disk for Leave. Join product merge is deferred. See [product.md](../requirements/product.md) and [privacy.md](../privacy.md).

Container: `iCloud.com.vil555tim.onecart`. Record types (`OneCartCoreDataV8`): `FamilySpace`, `Store`, `ShoppingList`, `Product`, `PurchaseHistory`, `HistoryItem`, `MemberProfile`, plus system `CKShare` on root `FamilySpace`. `MemberProfile` (V8, 1.6.0) carries each member's chosen name keyed by their CloudKit user record name, in the cart's zone, so the members list can name link-joined participants (REQ-AUTH-040); `CD_MemberProfile` must exist in the Production schema before a Release build writes it. No Core Data uniqueness constraints (CloudKit-incompatible); duplicates are soft-deleted via launch dedupe.

## Recovery, deadlines and widget writes

- Provisional personal-cart IDs are stored per account. Late imports reconcile local content by stable IDs before selecting the restored cart; pending mutations defer reconciliation and retry on completion. Neither the provisional source nor other shared families are deleted by selection.
- `HistoryItems.unique` selects one logical item per `(family ID, item ID)` for history and suggestions. Archive retries reuse existing logical purchases. This does not physically delete duplicate CloudKit history records.
- Account deletion unloads stores without deleting SQLite, checks every requested zone result, then marks confirmed cloud deletion before local cleanup. `account-deletion-state.json` survives interrupted cleanup. Pending cloud deletion loads original stores without mirroring; confirmed deletion finishes cleanup before reopening. Credentials clear only after cleanup succeeds.
- `CloudKitDeadline` resolves the caller once on result, timeout, or cancellation without waiting for a cancellation-insensitive SDK callback. A late cloud write remains possible; timeout is not proof of server-side cancellation.
- Widgets share the app session for persistent purchase actions. Commands contain account/family/product IDs and desired state, survive failed writes, and are acknowledged after Core Data saves. Cold-start, foreground and import-event drains reconcile pending commands. Commands older than a newer product edit are ignored; confirmed tombstones are acknowledged without recreating products. Legacy UUID-only toggle queues cannot identify an account or desired state and are not replayed. Snapshot counts describe the full cart, not just visible rows; sign-out and successful account deletion clear widget data.
- Both the app and widget extension bundle their own `PrivacyInfo.xcprivacy`. App Group defaults access is declared in each relevant target.

## Folder layout

```text
.
├── OneCart/          # Xcode product (Application, Features, Data, Shared, Resources, Tests)
├── docs/             # this set
├── assets/           # brand / store masters (not in app bundle)
├── Tooling/          # Engineering Runtime — see Tooling/justfile
└── justfile          # import Tooling/justfile
```

Full tree and commands: [README.md](../../README.md).


## Cart merge (LWW)

- Within one cart: duplicate `Product.id` → soft-delete loser via launch dedupe; prefer non-deleted, else newer `updatedAt`.
- On invite join: switch active to shared and hide personal from the session list — **no** private→shared product copy yet (deferred; `mergeFamilyContent` remains for later).
- Quantities are last-write-wins, never summed.
