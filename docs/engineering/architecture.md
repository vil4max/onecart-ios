# Architecture (Level 1 MVVM)

## Ladder decision

- **Level 1 — MVVM + POP services**
- **No Coordinator** — Welcome → tab shell; share URL handled at app root
- **No Clean Domain / UseCase modules** — repositories and CloudKit/Auth services are enough

## Product shell

Product policy (see [product.md](../requirements/product.md)): **one living family cart + CKShare path first.**

| In the shell now | Intentionally out of navigation |
|------------------|----------------------------------|
| Tabs: Корзина / История / Настройки; the app icon choice (it sets the accent); appearance and language follow the device | Unit / price input / Stores / catalog UI |
| Name-only inline add via `+` empty row + keyboard; category SF Symbol from keywords, optional on-device FM refine | Rich product editor / money UI |
| Invite + Revoke invite + leave from Настройки; members on the same screen | Multi-cart switcher |
| Hard cart sync (pull / appear / foreground) with nav «Updating…» | Toast / sync banner chrome |
| System alert for errors | — |

Store/catalog **UI modules are removed from the target**. Core Data still models `Store` and price fields for the CloudKit sync graph and older local rows. The app writes only a line's name and category (`ProductDraft`) and `status = "active"` on new lists, which v1.2.1 filters on; it no longer writes quantity, unit, price, note, URL, catalog, `serverRole`, `needsRemoteCreation`, History `total`, `memberNames` or `storeName`, and leaves values older builds stored untouched. The Production schema cannot drop fields, so `ManagedObjectModelTests` pins every attribute and relationship name. Do not re-wire catalog/store/price screens until two-device invite/sync is solid.

## Composition root

`AppSession` is a `@MainActor @Observable` root that owns the session state and thin wrappers;
SwiftUI tracks its properties and those of its `@Observable` collaborators directly (no
`ObservableObject`, Combine bridges or `objectWillChange`). Heavy work is delegated:

| Type | Role |
|------|------|
| `SessionBootstrapper` | SIWA restore / welcome retry; preserves pending account-deletion recovery |
| `CartContentStore` | lists / products / history pages; reload after viewContext reset; maps them once per reload into the screens' value snapshots |
| `CartSyncService` | `syncCart(reason:) → CartSyncOutcome`, viewContext reset/refetch, `contentRevision`, `isCartSyncing` |
| `CloudSyncCoordinator` | CloudKit observers, scheduled reload, maps sync outcome → `syncState` / alerts |
| `ConnectivityMonitor` | `NWPathMonitor` online/offline callbacks for the coordinator |
| `HouseholdCartCoordinator` | Ensure/adopt household cart + invitee shared-gone fallback |
| `InviteLinkPreparer` | Invite link cache / warm-up (silent soft-fail) |
| `FamilyShareOrchestrator` | invite link creation; owner ACL heal (does not reopen a revoked invite door); revoke invite (close door) |
| Repositories (`FamilyRepository`, `CartItemsRepository`, `PurchaseArchiver`, `CartDeduplicator`, `PersonalCartRestorer`, `MemberProfileStore`) | local Core Data reads and writes, one responsibility each, injected as protocols |
| `FamilyCloudSharing` (`CloudKitBackendService` + `FamilyInviteLinkBuilder`) | iCloud account, members, share lifecycle, user identity, private-zone account deletion |

iCloud reaches the session only through `FamilyCloudSharing`
(`OneCart/Data/CloudKit/FamilyCloudSharing.swift`): restored account, access, members, invite link,
revoke, ACL heal, remove member, leave, plus the `CloudUserIdentifying` and
`AccountCloudDataDeleting` members it inherits. `AppSession`, `SessionBootstrapper` and
`FamilyShareOrchestrator` take `any FamilyCloudSharing` in `init`; the live composition builds
`CloudKitBackendService`. Below it, every container call the share code makes (share lookup,
creation and persistence, the leave's zone purge, account status, user record ID) goes through
`CloudKitShareStoring` (`OneCart/Data/CloudKit/CloudKitShareStoring.swift`; live:
`LiveCloudKitShareStore`), injected into `CloudKitBackendService` and passed to
`FamilyInviteLinkBuilder`; tests use `FakeCloudKitShareStore`. Share changes are saved through
one path, `persistShare(_:in:)`, and the owner ACL heal and the invite door share
`applyReadWriteACL(to:reopenInviteDoor:in:)`. Shared-store edit rights come from `RecordPermissionChecking`, injected
into `CloudKitPermissionAuthorizer` (live: `ContainerRecordPermissions`, which asks the container).
No production path branches on the store kind: unit tests and the DEBUG welcome demo inject the
`#if DEBUG` `InMemoryFamilySharing` (`OneCart/Application/Demo/`), which answers as the app did on an
ephemeral store (one fixed account, scope-based access, no `CKShare`, a preview invite link, leave
and revoke without a server). The test session builders (`makeTestSession`,
`MembershipSessionFixture`) also pass `AllowAllRecordPermissions` and start the session ready.
`PersistenceController.isEphemeral` (temporary store files) shapes store setup and maintenance
and skips `acceptShareInvitations`, since an ephemeral store has no shared CloudKit store to
accept into. `mirrorsToCloudKit` (configured to mirror: not ephemeral and CloudKit enabled) gates
the cloud-import wait before a refresh and the CloudKit environment reconcile and stamp around
store loading; it reads the configuration, so it stays true while an interrupted account deletion
is recovered with CloudKit off.

Local data reaches the session and the coordinators through six repository protocols in
`OneCart/Data/Persistence/`, each declared in one file with its Core Data implementation:
`FamilyRepository` (`CoreDataFamilyRepository`: family reads on the view context, create, account
claim, rename, local discard of a left shared cart), `CartItemsRepository` (add, rename, category
refinement, purchase state, widget purchase replay, delete), `PurchaseArchiver` (Completed →
History), `CartDeduplicator` (stable-ID and same-name dedupe), `PersonalCartRestorer`
(`restoreProvisionalPersonalContent`) and `MemberProfileStore`. The implementations share
`RepositoryFetch` (live-row lookups by ID; a product lookup sorts in cart order, so a mutation by
ID changes the row the cart shows when a replica left two with that ID) and the
`PermissionGuardedRepository` write check over `PermissionAuthorizing`. `AppSession` holds five of them as
`any …` (`repository` is the `FamilyRepository`, which the membership paths use; only the
household coordinator takes `PersonalCartRestorer`);
`SessionBootstrapper` takes `FamilyRepository` and `CartDeduplicator`, `HouseholdCartCoordinator`
takes `FamilyRepository` and `PersonalCartRestorer`. `FamilySpaceRepository` remains as a
transitional facade: the live composition builds the six implementations through it, and tests and
seeding helpers keep its forwarding API; production code does not call the forwards. Coordinators
still read `persistence.container` for view-context work no repository owns: the sync reset
(`CartSyncService`), `processPendingChanges` after a mutation, the save before an invite
(`FamilyShareOrchestrator`), and the CloudKit observers.

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

Screens and ViewModels see values, not Core Data entities. The role protocols expose immutable
snapshots from `OneCart/Application/Services/CartValues.swift`: `CartList` and `CartItem`
(`SessionStateReading.cartLists`, `cartItems(inListID:)`) and `HistoryLine`
(`HistoryBrowsing.historyLines`, already deduplicated across replicas). `CartContentStore` maps
the entities into them once per reload, page load or product refresh
(`CartContentMapping.swift`), keeping the session's order (REQ-SHELL-010: newest to-buy first,
then completed). Mutations go back by ID (`CartEditing.addProduct(toListID:draft:)`,
`updateProduct(id:draft:)`, `setPurchased(productID:isPurchased:)`, `deleteProduct(id:)`); the
session resolves the live row on its own context and drops, with a log line, a tap whose row a
reload no longer has. `PrimaryListRule` picks the cart's list for values and entities alike.
While mapping, `CartContentStore` drops, from the entities as well as the values, a product
without an ID and a repeated product ID within one list (the first in cart order stays), and
shows no cart list when the primary list has no ID, so the cart, Siri, the widgets and the trip
count and pick the same lines. A `HistoryLine` is keyed by family and product ID, the identity
History deduplicates by (REQ-HIST-040). The exception is `SessionStateReading.activeFamilySpace`, still a `FamilySpace` entity: the screens
only test it for presence, and moving it touches every membership path. The ViewModel fakes hold
values, so their tests need no store; `CartFixture` stays for repository and mapping tests. Inside
the application layer (Siri intents, widgets, the shopping trip, the coordinators) the session
still works on entities.

Time and sleeping come from `AppClock` (`OneCart/Shared/Support/AppClock.swift`): the repositories,
the sync services, the invite preparer, the Settings share watchdog and the leave recovery take it
through their initializer (the session passes its clock; defaults are `.live`, which sleeps on the suspending clock like the timers
it replaced), and the launch ride reads it from the `appClock` environment value. Tests pass a
`TestClock` (`OneCart/Tests/Support/TestClock.swift`) and move time with `advance(by:)` instead of
waiting it out. The leave-purge deadline sleeps on the clock `CloudKitBackendService` takes. Not
on the clock yet: view-only animation timing, display dates, the other CloudKit deadlines
(`CloudKitDeadline` with a nanosecond timeout), the classifier timeout, and the Siri deadline and
Live Activity controller, which have their own seams.

Size guideline: the composition root stays around 200 lines and is split at 400 or more. `AppSession` stays a thin root; behavior lives in `AppSession+*.swift` extensions and the coordinators above.

## Key files

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
| `OneCart/Data/Persistence/PersistenceController+*.swift` | Store descriptions + diagnostics / wipe / env reconcile + account-deletion store state machine |
| `OneCart/Data/Persistence/OneCartManagedObjectModel.swift` | Programmatic `NSManagedObjectModel` |
| `OneCart/Data/Persistence/ManagedObjects.swift` | Core Data entity subclasses |
| `OneCart/Data/Persistence/FamilyRepository.swift`, `CartItemsRepository.swift`, `PurchaseArchiver.swift`, `CartDeduplicator.swift`, `PersonalCartRestorer.swift`, `MemberProfileStore.swift` | Repository protocols with their Core Data implementations; `PurchaseArchiver` has `archivePurchasedBefore` / `completePurchased` (Completed → history) |
| `OneCart/Data/Persistence/RepositoryFetch.swift`, `PermissionAuthorizing.swift`, `RepositoryError.swift`, `ProductDraft.swift`, `SoftDeletable.swift` | Shared lookups, write permission guard, errors, the add/rename draft, tombstone markers |
| `OneCart/Data/Persistence/FamilySpaceRepository.swift` | Transitional facade: builds the repositories; forwarding API for tests |
| `OneCart/Data/CloudKit/` | Split: `FamilyCloudSharing` seam, `CloudKitShareStoring` container seam and share mutation path, models, errors, share ACL/branding, `CloudKitDeadline`, permissions (`RecordPermissionChecking`), backend, invite builder |
| `OneCart/Application/Demo/InMemoryFamilySharing.swift` | DEBUG-only iCloud stand-in for unit tests and the welcome demo |
| `OneCart/Data/Authentication/AppleSignInService.swift` | Sign in with Apple, behind `AppleSignInAuthenticating`; that protocol, the credential, state, error, store protocol, Keychain store and presentation anchor each in their own file beside it |
| `OneCart/Features/Onboarding/WelcomeView.swift` | SIWA + cart pitch + iCloud connect |
| `OneCart/Features/Shopping/HomeView.swift` | Cart home |
| `OneCart/Features/Shopping/ShoppingListView.swift` | Active list composition + inline add/edit; To Buy / Completed |
| `OneCart/Features/Shopping/CartProductRow.swift` | Product row, purchase toggle, category thumbnail |
| `OneCart/Features/Shopping/CartAddComposer.swift` | Add field and `+` button |
| `OneCart/Features/Shopping/HistoryViews.swift` | History by day (`historyHasMore` / load more); read-only |
| `OneCart/Features/Shopping/HistoryDetailViews.swift` | Day detail product list |
| `OneCart/Features/Shopping/CartChromeViews.swift` | Empty / read-only / unavailable chrome |
| `OneCart/Shared/Support/ProductCategory.swift` | Metro categories, inference, section grouping |
| `OneCart/Shared/Support/CategoryClassifier.swift` | Keyword + on-device FM category refine |
| `OneCart/Features/Account/AccountView.swift` | Account tab shell |
| `OneCart/Features/Account/AccountViewModel.swift` | Share / leave / revoke / rename / display-name / icon presentation state |
| `OneCart/Features/Account/AccountRows.swift` | Member and action rows |
| `OneCart/Features/Account/CartShareActivityBridge.swift` | Share sheet activity items / metadata |
| `Tooling/` | Shared build and CI tooling (`backend/`, style configs) |

## Trade-offs (recovery / sync)

| Choice | Why |
|--------|-----|
| `load()` preserves stores on transient failures | Explicit welcome recovery requires a store-load failure (`WelcomeFailureCause.storeLoad`, armed only by `persistence.load()` and consumed by one Retry) and a diagnostics copy; errors from later bootstrap steps never arm the wipe, because they can come from unsynced local edits; a confirmed account-deletion marker finishes previously authorized cleanup before reopening |
| `CartSyncOutcome` + failed ≠ synchronized | Coalesced callers receive the final queued refresh outcome; recovery mode keeps `.failed` |
| History page size 30 + offset fetch | Avoid loading full purchase history into memory; UI “show more” calls `loadMoreHistory` |
| Device-local profile | Display name and local avatar/banner preferences are separate from CloudKit membership |
| CI split ([ADR 0003](../decisions/0003-ci-split.md), [ADR 0004](../decisions/0004-tag-gated-testflight.md)) | GitHub Actions runs tests on push/PR; an annotated `tf-` tag fast-forwards `testflight`; Xcode Cloud only archives from `testflight` |

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

DEBUG demo mode (`-oneCartDemoUI`) opens the same filenames under `Application Support/OneCartDemo/<role>/` and keeps its Sign in with Apple credential in memory, so seeded demo rows never reach the real stores, CloudKit, or the Keychain. `-oneCartDemoReset` wipes that role's demo store before seeding; the UI smoke suite (`OneCartUITests`, run by the shared scheme's Test action) launches every test with it so no state carries between runs.

New household spaces and children go to the private store. After `CKShare` accept, the shared space appears in the shared store. Local saves are immediate; CloudKit syncs when online.

There is **no public API to force** a CloudKit import/export mirror ([TN3163](https://developer.apple.com/documentation/technotes/tn3163-understanding-the-synchronization-of-nspersistentcloudkitcontainer) / [TN3164](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer)). The app schedules best-effort hard refresh after import events, pull-to-refresh, cart appear, and foreground. ViewContext uses `NSMergeByPropertyStoreTrumpMergePolicy` so remote store wins over stale in-memory values. User-facing failures use a system alert; transient share create retries honor `CKError.retryAfterSeconds` when present.

`CKShare` uses `publicPermission = .readWrite` (link-join). Owner **Revoke invite** sets `publicPermission = .none` (no new joins; members stay; same `FamilySpace` UUID). Owner ACL heal upgrades participant write ACL but must not reopen a revoked public door; **Share** / invite create reopens with `reopenInviteDoor`. After Accept, reload always prefers a shared `FamilySpace` and hides personal from the session list; personal stays on disk for Leave. There is no join product merge. See [product.md](../requirements/product.md) and [privacy.md](../privacy.md).

Container: `iCloud.com.vil555tim.onecart`. Record types (`OneCartCoreDataV8`): `FamilySpace`, `Store`, `ShoppingList`, `Product`, `PurchaseHistory`, `HistoryItem`, `MemberProfile`, plus system `CKShare` on root `FamilySpace`. `MemberProfile` (V8, 1.6.0) carries each member's chosen name keyed by their CloudKit user record name, in the cart's zone, so the members list can name link-joined participants (REQ-AUTH-040); `CD_MemberProfile` must exist in the Production schema before a Release build writes it. No Core Data uniqueness constraints (CloudKit-incompatible); duplicates are soft-deleted via launch dedupe. Debug and Release entitlements both pin the container environment to Production, so share mutations carry no per-share environment check; local stores are wiped before load only when the stored environment marker is exactly `development` (defensive: no shipped build stamped it, since the marker arrived with the pin), and every successful load stamps `production`.

## Recovery, deadlines and widget writes

- Provisional personal-cart IDs are stored per account. Late imports reconcile local content by stable IDs before selecting the restored cart; pending mutations defer reconciliation and retry on completion. Neither the provisional source nor other shared families are deleted by selection.
- `HistoryItems.unique` selects one logical item per `(family ID, item ID)` for history and suggestions. Archive retries reuse existing logical purchases. This does not physically delete duplicate CloudKit history records.
- Account deletion unloads stores without deleting SQLite, checks every requested zone result, then marks confirmed cloud deletion before local cleanup. `account-deletion-state.json` survives interrupted cleanup. Pending cloud deletion loads original stores without mirroring; confirmed deletion finishes cleanup before reopening. Credentials clear only after cleanup succeeds.
- `CloudKitDeadline` resolves the caller once on result, timeout, or cancellation without waiting for a cancellation-insensitive SDK callback. A late cloud write remains possible; timeout is not proof of server-side cancellation. An operation that finishes after the caller was released is reported once through `onLateCompletion`.
- Leave (REQ-SHARE-050): the zone purge runs under `CloudKitDeadline` with `leaveTimedOut` after `CloudKitBackendService.leavePurgeTimeout`. On a timeout the session shows the alert and starts its leave recovery, which retries the fallback to the personal cart on the `AppClock` and also runs one pass when the late purge reports in through `leaveFamily(objectID:onLatePurgeCompletion:)`; a late purge that leaves the shared cart behind does not end the timed passes.
- Widgets share the app session for persistent purchase actions. Commands contain account/family/product IDs and desired state, survive failed writes, and are acknowledged after Core Data saves. Cold-start, foreground and import-event drains reconcile pending commands. Commands older than a newer purchase change of the product are ignored (a rename or category refinement does not count); confirmed tombstones are acknowledged without recreating products. Legacy UUID-only toggle queues cannot identify an account or desired state and are not replayed. Snapshot counts describe the full cart, not just visible rows; sign-out and successful account deletion clear widget data.
- Both the app and widget extension bundle their own `PrivacyInfo.xcprivacy`. App Group defaults access is declared in each relevant target.
- Files compiled into both the app and the widget extension (`OneCart/Shared/Widgets/`, `AppAccentColor`, `ProductCategory`, `OneCartLog`) hold plain models and logic: they import Foundation or OSLog (plus ActivityKit or AppIntents where the type requires it), and model values never read the App Group or call WidgetCenter. SwiftUI presentation lives in per-target extension files (`ProductCategory+SwiftUI.swift` in the app, `WidgetCartSnapshot+SwiftUI.swift` in the widget). `WidgetSnapshotStore` takes its timeline reload as a closure; each target defines its live `shared` store with `WidgetCenter` reloads, and the store, not the snapshot, reads the stored accent (`withStoredAccent`). Known exceptions: `OneCartPalette` is shared SwiftUI presentation that also reads the App Group accent at launch, and the two `LiveActivityIntent`s keep their dual membership and `#if ONECART_WIDGET_EXTENSION` branches.

## Folder layout

```text
.
├── OneCart/          # Xcode product (Application, Features, Data, Shared, Resources, Tests)
├── docs/             # this set
├── assets/           # brand / store masters (not in app bundle)
├── Tooling/          # Shared build and CI tooling — see Tooling/justfile
└── justfile          # import Tooling/justfile
```

Full tree and commands: [README.md](../../README.md).


## Cart merge (LWW)

- Within one cart: duplicate `Product.id` → soft-delete loser via launch dedupe; prefer non-deleted, else newer `updatedAt`, else a stable order. `Product.updatedAt` moves on purchase-state changes and deletes, not on renames or category refinements, because a queued widget purchase compares it.
- On invite join: switch active to shared and hide personal from the session list — **no** private→shared product copy; there is no join merge code. A new-device import copies provisional personal content by stable IDs (`restoreProvisionalPersonalContent`, REQ-SYNC-040).
- Quantities are last-write-wins, never summed.
