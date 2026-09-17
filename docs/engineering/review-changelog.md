# OneCart PR review changelog

Historical scope: `feat/living-cart-and-tabs` against `main` (RC/NC/FU entries below).
Current audit fixes are tracked separately in the table below.
Audience: human reviewer + review agent

## September 2026 reliability audit

Each row is one logical repair and one commit. Historical RC entries below describe their original review scope and are not a current branch manifest.

| Finding | Repair | Regression evidence |
|---------|--------|---------------------|
| 1 | Shared-cart selection retains other families | SharedCartJoinTests, HouseholdEnsureTests |
| 2 | Background invite preparation never opens a revoked door | ShareLinkJoinACLTests |
| 3 | Validate every CloudKit zone deletion result | AccountDeletionTests |
| 4 | Preserve SQLite until cloud deletion succeeds; recover/retry cleanup | AccountDeletionTests disk recovery cases |
| 5 | Bundle app and widget privacy manifests | Built app/extension resource inspection |
| 6 | Reconcile provisional personal cart after late import | HouseholdEnsureTests, FamilyCartMergeTests |
| 7 | Deduplicate logical history across archive replicas | PurchaseSessionTests, CartSuggestionsEngineTests |
| 8 | Coalesced sync callers receive failure outcomes | FragileSyncOutcomeTests |
| 9 | SDK callbacks cannot prolong caller deadlines | InviteLinkPreparerTests |
| 10 | Persist and acknowledge widget purchase commands | WidgetSnapshotTests |
| 11 | Widget counts include products outside its display window | WidgetSnapshotTests |
| 12 | Clear widget data on sign-out/account deletion | WidgetPrivacyCleanupTests |

Run `just verify` for the combined code state. Signed-device checks and release status remain separate; see [release.md](../operations/release.md).

## Current layout (post-reorg)

Product: `OneCart/`. Docs index: [docs/README.md](../README.md). Tooling configs under `Tooling/`. Root `justfile` imports `Tooling/justfile`.

## How to review
1. Read this file top to bottom by ID.
2. For each `done` item, open listed paths and confirm behavior/notes.
3. Run verification commands; record pass/fail.
4. Do not invent extra scope; anything not listed is out of PR unless marked follow-up.

## Intentional non-changes
- NC01 Bundle ID com.vil555tim.onecart
- NC02 CloudKit container iCloud.com.vil555tim.onecart
- NC03 Core Data store filenames (OneCart-private.sqlite / OneCart-shared.sqlite)
- NC04 No Coordinator / Clean Domain modules
- NC05 No multi-cart UX
- NC06 Deployment target iOS 26 (was iOS 15; aligned project/tests with app target)
- NC07 No Apple Family member-list / same-family / share-to-all-family APIs
- NC08 No IAP / Family Sharing subscriptions in this PR
- NC09 CI stays Xcode Cloud release-only (no pre-merge GitHub Actions in this train) — superseded 2026-09-16 by [ADR 0003](../decisions/0003-ci-split.md)
- NC10 Keep CKShare link-join `publicPermission = .readWrite` while the invite door is open; owner **Revoke invite** sets `.none` until Share again (ACL heal must not reopen)

## Changes

### RC01 — Engineering Runtime harness
- Status: done
- Paths: justfile, Tooling/justfile, Tooling/runtime.yml, Tooling/scripts/, Tooling/HostBuild/, Tooling/Brewfile, Tooling/.swiftformat, Tooling/.swiftlint.yml, AGENTS.md, .gitignore
- What changed: ios-engineering-runtime install (--personal); configs later moved under `Tooling/`
- How to verify: `just doctor`

### RC02 — SwiftFormat baseline
- Status: done
- Paths: OneCart/**/*.swift
- How to verify: `just format` idempotent

### RC03 — Rename App → OneCart
- Status: done
- Paths: OneCart/OneCart.xcodeproj, scheme OneCart, Tooling/runtime.yml
- What changed: project/target/product/scheme renamed; bundle ID unchanged
- How to verify: `just build`

### RC04 — Folder layout Application/Features/Data/Shared
- Status: done
- Paths: OneCart/Application/, OneCart/Features/, OneCart/Data/, OneCart/Shared/, OneCart/Resources/
- How to verify: open project; `just build`

### RC05 — AppSession + Level 1 MVVM composition root
- Status: done
- Paths: OneCart/Application/AppSession.swift, OneCart/Features/*/WelcomeViewModel.swift, ShoppingViewModel.swift, SettingsViewModel.swift
- What changed: AppSession composition root; thin feature ViewModels wired for onboarding/home/settings
- How to verify: app boots; Welcome/Settings/Home use ViewModels

### RC06 — Split Shopping/Catalog/Stores/Settings god files
- Status: done
- Paths: OneCart/Features/Catalog/CatalogParsers.swift, OneCart/Features/Stores/StoreLocatorModel.swift
- What changed: extracted catalog parsers and store locator model; remaining UI monoliths tracked as FU05 polish
- How to verify: `just build`; types live in new files

### RC07 — String Catalog + system locale
- Status: done
- Paths: OneCart/Resources/Localizable.xcstrings, Welcome/Home/Settings/tabs strings
- What changed: String Catalog en/ru/uk with human copy; language follows system locale (no in-app language picker); tech jargon removed from Welcome footer
- How to verify: change device/simulator language; Welcome and tabs follow system

### RC08 — v1.1 Who is OneCart for + Household flow
- Status: done (superseded for verify path)
- Paths: OneCart/Features/Onboarding/WelcomeView.swift, OneCart/Application/AppSession.swift
- What changed: originally audience picker + auto-create Household cart
- How to verify now: fresh install → Sign in with Apple → Home (one household cart). Audience picker removed in later simplify-onboarding work.

### RC09 — Default cart title «Наши покупки» + household-default identity
- Status: done
- Paths: OneCart/Data/Persistence/ManagedObjects.swift, OneCart/Data/Persistence/FamilySpaceRepository.swift, OneCart/Shared/Support/FamilyCartMerge.swift, OneCart/Application/AppSession.swift
- What changed: `isHouseholdDefault`; default title via catalog; legacy name migration; starter delete by flag
- How to verify: unit tests `testDeletableStarterFamilyDetection`, model attribute present

### RC10 — CKShare publicPermission .none + Apple Family positioning docs
- Status: superseded by RC21
- Paths: OneCart/Data/CloudKit/CloudKitServices.swift, docs/requirements/product.md
- What changed: `publicPermission = .none`; docs state positioning vs missing Family APIs
- How to verify: grep publicPermission; read product doc

### RC11 — Merge policy / uniqueness / concurrency hardening
- Status: done (uniqueness claim superseded)
- Paths: PersistenceController Sendable documentation + logger subsystem fix; later PR removed CloudKit-incompatible unique constraints
- What changed: object-trump merge policy; Sendable boundary notes; uniqueness constraints must stay empty for CloudKit
- How to verify: `ManagedObjectModelTests` asserts `uniquenessConstraints` empty on all entities

### RC12 — Tests split + ViewModel coverage
- Status: done
- Paths: OneCart/Tests/OneCartTests.swift, FamilyCartMergeTests.swift, ManagedObjectModelTests.swift
- What changed: split merge/model tests; defaults/flags covered
- How to verify: simulator OneCartTests green

### RC13 — Lint / just verify green
- Status: done
- Paths: Tooling/.swiftlint.yml
- What changed: thresholds relaxed for remaining monoliths; lint 0 serious
- How to verify: `just lint`; `just build`; tests (destination id=simulator to avoid device hangs)

### RC14 — Docs architecture + product + ADR sync
- Status: done
- Paths: docs/engineering/architecture.md, docs/requirements/product.md, docs/operations/release.md, docs/planning/legacy-migration.md, docs/README.md, README.md, AGENTS.md, docs/engineering/review-changelog.md
- How to verify: read docs/README.md; AGENTS points there

### RC15 — Xcode project under OneCart/ (single product directory)
- Status: done
- Paths: OneCart/OneCart.xcodeproj, OneCart/{Application,Features,Data,Shared,Resources,Tests}/, Tooling/
- What changed: product lives in `OneCart/`; nested Xcode groups match folders; harness under `Tooling/HostBuild/`
- How to verify: open `OneCart/OneCart.xcodeproj`; `just doctor`; `just build`; `just test`

## Follow-ups (explicitly not in this PR)

Living note (Runtime / Global Order): harness slice is `Tooling/` **0.2.2** with `Tooling/backend/` (historical RC paths that say `HostBuild/` are obsolete). Feature Account UI lives under `OneCart/Features/Account/` (not `Settings/` / `MoreView`). Style configs `Tooling/.swiftlint.yml` / `.swiftformat` are **app-owned** (see `Tooling/docs/style-config.md`).

- FU01 Multi-cart UI (personal + N invited)
  - One durable personal cart + N invited shared carts in a switcher
  - Personal accent color vs invited/family chrome (readable without reading labels)
  - Move items between personal and invited
  - Account share/members bound to selected cart
  - Naming: app brand vs personal title vs owner-set shared title
  - Board: https://github.com/orgs/vil4labs/projects/2 (App=OneCart)
  - Not in cart-as-core v1 (one active UX; personal hidden while on shared)
- FU15 History size / retention (no Clear History UI; pagination/optimize later)
- FU02 iOS 17 @Observable migration for ViewModels
- FU03 Expand String Catalog beyond Welcome/cart title (full UI) — **superseded**: UI strings are in `Localizable.xcstrings` (en/ru/uk)
- FU04 IAP + Family Sharing subscriptions
- FU05 Further split Catalog/Shopping UI monoliths — **superseded** for current shell: Catalog/Stores UI removed; Shopping/Account split under Global Order (`CartProductRow`, `AccountViewModel`, …)
- FU06 Replace PersistenceController @unchecked Sendable with stricter isolation
- FU07 Scraper HTML fixtures / Keychain PII / profile file protection
- FU08 Re-enable Stores tab / store-bound lists **only after** two-device invite+sync is solid
- FU09 Catalog-first add / WebKit price refresh as optional path (not blocking quick name add)
- FU10 Rich product editor fields (qty/unit/price/notes) behind a secondary “details” action
- FU11 Optional Settings surface (appearance) only if system appearance proves insufficient
- FU12 Pre-merge GitHub Actions — done 2026-09-16, see [ADR 0003](../decisions/0003-ci-split.md)
- FU13 Swift 6 language mode / strict concurrency across targets
- FU14 MetricKit / XCUITest smoke beyond unit fragile suite

### RC16 — Stability-first minimal shell (docs + UX)
- Status: done (this train)
- Paths: `RootView` tabs, `QuickAddProductSheet`, `docs/requirements/product.md`, `docs/engineering/architecture.md`, `docs/operations/release.md`
- What changed: Cart+Settings only; thumb FAB + name-only add; invite on cart; history in Settings; documented cuts toward stability
- How to verify: read [core.md](../core.md) P4; + opens name-only add; no Stores tab. Tab layout superseded — current shell has three tabs, see [product.md](../requirements/product.md) § Shell
- Do not invent scope: restoring Stores/catalog is FU08/FU09, not required for merge

### RC17 — Cart-only shell (no Settings prefs)
- Status: done (this train)
- Paths: `RootView`, `ShoppingViews`, `CartManagementSheet`, `DevicePreferences`, Catalog/Stores/Settings UI removed, `Localizable.xcstrings`, docs
- What changed: no Settings tab; share from cart home; copy uses «корзина»; default title «Список покупок»; theme/unit prefs removed; dead Stores/Catalog UI deleted
- How to verify: after Welcome only cart UI; «Поделиться» on cart; overflow → participants/history/profile; no theme/unit screens
- Do not invent scope: restoring Stores/catalog/Settings is FU08/FU09/FU11, not required for merge

### RC18 — Surface CloudKit Production schema failure as alert
- Status: done (this train)
- Paths: `CloudKitServices.swift`, `AppSession.swift`, `OneCartTests.swift`, `docs/operations/release.md`
- What changed: detect `CD_*` production-schema errors from nested userInfo; show one session alert on mirroring failure (was only `lastSyncError`); build **1.2.1 (3)**
- How to verify: unit test `testCloudKitUserFacingErrorMapsProductionSchema*`; on TF without Deploy, alert mentions CloudKit Console Deploy
- Do not invent scope: **Deploy Schema Changes to Production** is still a Console-only owner action — code cannot create `CD_ShoppingList` in Production

### RC19 — Slim Settings; History tab (superseded by RC17 merge)
- Status: superseded
- What changed: briefly landed History tab + slim Settings on main; then PR #17 merged cart-only shell (History as sheet from cart menu)
- Build after merge: **1.2.1 (5)**

### RC20 — Living cart: trolley metaphor, three tabs, dead-code purge
- Status: done (this train)
- Paths: `ShoppingViews.swift`, `RootView`, `AppSession.swift`, `FamilySpaceRepository.swift`, `WelcomeView.swift`, `ProductMedia.swift`, `Localizable.xcstrings`, `OneCart/Tests/**`, `docs/**`, `assets/store/screenshots/01-welcome.png`
- What changed: checkbox now means «в тележке», «Завершить покупки» archives **only checked items** (`completePurchased`) and keeps the rest in the living cart; tabs Корзина / История / Аккаунт with share on the Account screen; quick add is a medium sheet that dismisses after one item; history grouped by session/month; Welcome explains the three steps; price / unit / pseudo-catalog UI, StoreMark assets, dead multi-list and store APIs and stale strings removed; monolithic `BusinessLogicTests` / `OneCartTests` split into thematic suites over shared `CartTestSupport`
- How to verify: `just build`; tests 44 pass; check an item → progress counts it → «Завершить покупки» → only checked items appear in История, unchecked stay in the cart; no money or «шт.» anywhere in the UI
- Do not invent scope: price input, units and rich product fields stay FU10; Stores/catalog stay FU08/FU09
- Core Data model unchanged (CloudKit schema compatibility)

### RC21 — CKShare link-join for forwarded invites
- Status: done (this train); RC23 closes re-share ACL gap
- Paths: `CloudKitServices.swift`, `docs/requirements/product.md`, `docs/engineering/architecture.md`, `docs/decisions/0002-cloudkit-native-backend.md`, `README.md`, `docs/engineering/review-changelog.md`
- What changed: `publicPermission = .readWrite` so anyone with the share URL can Accept (Telegram/Messages forwards); supersedes RC10 `.none` ACL; Apple Family positioning still forbids Family Sharing membership APIs
- How to verify: `grep publicPermission` shows `.readWrite`; owner opens Share once on a build with RC23 so existing shares persist ACL; invitee taps forwarded `icloud.com/share/...` → Accept → shared cart
- Do not invent scope: no Universal Links, custom schemes, or `UICloudSharingController`

### RC23 — Persist link-join ACL on existing share URL fast path
- Status: done (this train); RC28 upgrades participant write ACL
- Paths: `CloudKitServices.swift`, `docs/engineering/review-changelog.md`
- What changed: reusing an already-published share URL now background-persists `publicPermission = .readWrite` (and branding), not branding alone — fixes Item Unavailable on Telegram forwards for pre-RC21 shares
- How to verify: owner Share again from Account; same or updated link opens for a second Apple ID that is not a private invitee
- Do not invent scope: no new share UX, no deleting old CKShares

### RC28 — Upgrade CKShare participant write permission (fix readOnly invitees)
- Status: done (this train)
- Paths: `CloudKitServices.swift`, `SharedCartJoinTests.swift`, `docs/engineering/review-changelog.md`
- What changed: `applyReadWriteACL` now also sets every non-owner `participant.permission = .readWrite` (not only `publicPermission`); invite fast path / finalize awaits `persistUpdatedShare` (8s ceiling, then background retry) before handing out the URL — fixes «You don't have permission to edit this cart» when `canUpdateRecord` is false for readOnly members
- How to verify: owner opens «Поделиться корзиной» once on this build (upgrades existing members); invitee can check items / quick-add without permission alert; `ShareLinkJoinACLTests` green
- Do not invent scope: no CloudKit Dashboard changes, no UICloudSharingController, no new invite UX

### RC24 — Scene-based CKShare accept delivery
- Status: done (this train)
- Paths: `SceneDelegate.swift`, `AppDelegate.swift`, `OneCart.xcodeproj`, `docs/engineering/review-changelog.md`
- What changed: SwiftUI scene apps receive share metadata via `windowScene(_:userDidAcceptCloudKitShareWith:)` and cold-start `connectionOptions.cloudKitShareMetadata`; AppDelegate path kept as fallback; existing `acceptPendingCloudKitShares` → `adoptSharedFamilyCartIfNeeded` unchanged (one living cart)
- How to verify: invitee taps `icloud.com/share/...` (cold or warm) → Accept → shared cart replaces private starter; items from owner visible
- Do not invent scope: no Universal Links

### RC25 — Confirm before replacing cart on share join
- Status: superseded by RC27 (join alert removed)

### RC26 — Auto-adopt empty starter; alert dismiss is not Cancel
- Status: superseded by RC27 (join alert removed)

### RC27 — Remove share-join confirm alert
- Status: done (this train)
- Paths: `AppSession.swift`, `RootView.swift`, `SharedCartJoinTests.swift`, `docs/requirements/product.md`, `docs/engineering/review-changelog.md`
- What changed: after shared cart is available locally, always `adoptSharedFamilyCartIfNeeded` (merge/archive private); no Join/Cancel UI
- How to verify: invitee Accept → shared items without alert; `SharedCartJoinTests` cover empty adopt + content merge
- Do not invent scope: no new Account CTA

### RC22 — Deployment target iOS 26
- Status: done (this train)
- Paths: `OneCart.xcodeproj/project.pbxproj`, `ShoppingViews.swift`, `ProfileView.swift`, `README.md`, `docs/engineering/review-changelog.md`
- What changed: project + test targets aligned to `IPHONEOS_DEPLOYMENT_TARGET = 26.0` (app target already 26.0); clears XC Cloud `CKRecord`/`Sendable` availability warnings; drop iOS 16 `#available` for medium sheet
- How to verify: all `IPHONEOS_DEPLOYMENT_TARGET` = 26.0; Archive without CKRecord Sendable warnings
- Do not invent scope: no `@Observable` migration (FU02)

### RC29 — Shared cart sync UI, ACL heal, delete cart, decompose, audit hygiene
- Status: done (this train)
- Paths: `CartSyncService.swift`, `FamilyShareOrchestrator.swift`, `CloudKit/*.swift` (split), `AppSession.swift`, `ShoppingViews.swift`, `HistoryViews.swift`, `CartChromeViews.swift`, `MoreView.swift`, `PersistenceController.swift`, `Localizable.xcstrings`, `Info.plist`, `PrivacyInfo.xcprivacy`, splash assets, `docs/engineering/architecture.md`, `docs/planning/legacy-migration.md`, `docs/requirements/product.md`, `docs/privacy.md`, `docs/operations/release.md`, `README.md`, `AGENTS.md`
- What changed: StoreTrump on viewContext; hard cart sync (pull/appear/import/foreground) with nav Updating chrome; owner ACL heal; owner Delete cart rotates invite URL; invitee shared-gone fallback alert; CloudKit god-file split + CartSync/Share orchestration extract; History/CartChrome UI split; removed LegacyMigration + CoreLocation/location plist; dropped PreciseLocation/PhysicalAddress from PrivacyInfo; `CKError.retryAfterSeconds` in share retry; splash PNG compress; CartSync/ShareACL `os.Logger` (no full share URLs); docs aligned to new layout
- How to verify: unit tests green; Max check → Tim pull/appear sees trolley counts; Tim edits without permission alert; Max Delete cart → Tim fallback alert + new Share URL; files under CloudKit/ and Shopping/ are smaller than pre-split monoliths
- Do not invent scope: no GitHub Actions / Xcode Cloud config change (see NC09); no MetricKit/XCUITest/Swift 6 strict; no revert of link-join `.readWrite`

### RC30 — Recovery sync safety + session split + history pages
- Status: done (this train)
- Paths: `PersistenceController.swift`, `CartSyncService.swift`, `CartContentStore.swift`, `SessionBootstrapper.swift`, `CloudSyncCoordinator.swift`, `ProfileStore.swift`, `AppSession.swift`, `HistoryViews.swift`, `FragileStoreLoadTests.swift`, `FragileSyncOutcomeTests.swift`, `HistoryPaginationTests.swift`, `ProfileStoreTests.swift`, `docs/engineering/architecture.md`, `docs/engineering/review-changelog.md`
- What changed: non-destructive store `load()` + diagnostics before explicit wipe; `CartSyncOutcome` so failed hard-refresh ≠ synchronized; extracted bootstrap / content / cloud sync / profile stores; history fetch page size 30 + `loadMoreHistory`; fragile-test matrix documented
- How to verify: F1–F10 green via `test_sim`; grep checklist — no `hardReset` in `load()` / `prepare`; sync failure leaves `.failed`
- Do not invent scope: NC09 still no pre-merge GitHub Actions; Swift 6 strict and MetricKit remain FU

### RC31 — God-file split train (composition root ~200)
- Status: done (this train)
- Paths: `AppSession.swift` + `AppSession+*.swift`, `HouseholdCartCoordinator.swift`, `InviteLinkPreparer.swift`, `SessionTypes.swift`, `HomeView.swift` / `ShoppingListView.swift` / `QuickAddProductSheet.swift`, `FamilySpaceRepository+*.swift`, `OneCartManagedObjectModel.swift`, `PersistenceController+*.swift`, `LaunchChrome.swift`, `CartShareActivityBridge.swift`, `HistoryDetailViews.swift`, `ConnectivityMonitor.swift`, characterization tests under `OneCart/Tests/`, `docs/engineering/architecture.md`, `docs/engineering/review-changelog.md`
- What changed: split former god-files under hard trigger 400+; `AppSession` composition root ~200 lines; coordinators/extensions own household, invite warm-up, mutations, membership, selection; shopping / persistence / soft-band UI extracts; F1–F10 invariants unchanged
- How to verify: F1–F10 + `just verify`; `AppSession.swift` ≤ ~200; former ≥400 owners under 400 (entity subclasses in `ManagedObjects.swift` remain data-model density)
- Do not invent scope: no product feature restore (stores/catalog/price UI); no silent/soft-fail policy changes; NC09 unchanged

### RC32 — Completed + overnight History by day (Metro categories)
- Status: done (this train)
- Paths: `ShoppingListView.swift`, `HistoryViews.swift`, `HistoryDetailViews.swift`, `FamilySpaceRepository+Products.swift`, `AppSession+CartMutations.swift`, `AppSession.swift`, `ManagedObjects.swift`, `CategoryClassifier.swift`, `Localizable.xcstrings`, `PurchaseSessionTests.swift`, `CartItemsTests.swift`, `ProductCategoryInferenceTests.swift`, `docs/requirements/product.md`, `docs/engineering/architecture.md`, `docs/operations/release.md`, `README.md`, `AGENTS.md`
- What changed: no manual «Finish shopping»; section **Completed**; FAB `+` without bottom plate; overnight `archivePurchasedBefore` on appear/foreground; History grouped by purchase day (read-only); Metro-style categories + icons; Completed cannot swipe-delete; dead QuickAdd sheet / history-delete UI removed
- How to verify: `just verify`; PurchaseSession / CartItems / ProductCategory suites; manual: check → Completed → next day open → History day cell → product list; no Delete day
- Do not invent scope: no restore of Done CTA, history delete, stores/catalog/price UI

## Verification
- `just doctor`
- `just lint` (0 serious)
- `just build`
- `just test` / `just verify`
- Manual: Welcome → SIWA → Корзина → `+` → name → keyboard Done → check row → **Completed** → next calendar day open app → item in **History** by day (read-only)
- Manual (device): «Аккаунт» → Поделиться корзиной → accept on second device → shared cart replaces/merges private starter; invitee can add/check items (not readOnly); errors via system alert
- Manual (existing readOnly member): owner opens «Поделиться корзиной» once after RC28 → invitee retries edit without re-accept
- Manual (RC29): Max marks Completed → Tim appear/pull sees Updating + matching counts; owner Delete cart rotates link
- Manual (RC30): failed sync shows failed state (not “synced”); welcome network retry does not wipe SQLite; History “show more” loads next page
- Manual (RC31): launch ride → welcome/main unchanged; invite share sheet still works; connectivity offline→online still schedules reload
- Manual (RC32): no Finish shopping / Delete day; History caption explains overnight archive; category icon + label on cart rows
- See also [release.md](../operations/release.md) § Preflight + §3

### RC30 — Cart-as-core (durable cart, no Recreate)
- Status: done (this train)
- Paths: HouseholdCartCoordinator, FamilySpaceRepository+Merge, FamilyShareOrchestrator, AppSession+Membership, MoreView, FamilyCartMerge, CartHaptics, MemberJoinNotifier, docs
- What changed: accept/ensure always adopts shared as active; personal FamilySpace kept on join; LWW join merge; Recreate removed; Revoke invite closes door; participants can share link; owner rename cart; personal default title; local notify on new member; haptics on primary actions; history never cleared (FU15)
- How to verify: unit tests above; two-device accept → Tim sees Max cart as member; leave → same personal UUID; revoke → new joins blocked
- Do not invent scope: multi-cart UI is FU01 only

### RC33 — Cart To Buy by category sections
- Status: done (this train)
- Paths: ShoppingListView, ProductCategory.groupedSections, ProductCategoryInferenceTests, docs/requirements/product.md
- What changed: living cart To Buy groups into Metro category sections; Completed and History stay flat lists; row category caption hidden under section headers
- How to verify: unit test grouping order; device — milk/bread/other land in separate To Buy sections; mark Completed → flat Completed list; History unchanged
- Do not invent scope: no category grouping in History or Completed

### RC34 — Revoke door vs ACL heal + notify seed
- Status: done (this train)
- Paths: CloudKitShareSupport.applyReadWriteACL, CloudKitBackendService.revokeInviteLink, MemberJoinDiff, AppSession+Membership rename personal, docs/requirements/product.md, SharedCartJoinTests
- What changed: ACL heal no longer reopens `publicPermission = .none`; invite create passes `reopenInviteDoor`; revoke no-share/env mismatch throws; member-join first snapshot seeds without notify; personal Rename edits nickname (one title pattern)
- How to verify: ShareLinkJoinACLTests preserve/reopen; MemberJoinDiffTests seed; rename personal → `cart.personal_title`; device revoke then syncCart leave door closed until Share again
- Do not invent scope: Production schema deploy remains ops

### RC35 — Accept = shared only; defer join merge
- Status: done (this train)
- Paths: AppSession+FamilySelection.reload, HouseholdCartCoordinator.adoptSharedFamilyCartIfNeeded, MoreView Account cart title, SharedCartJoinTests, docs/requirements/product.md
- What changed: while any shared cart exists, session list/active cart are shared only (personal stays on disk for Leave); join no longer merges private products into shared; Account shows active cart title
- How to verify: accept/ensure → active shared, `familySpaces` has no personal; private products absent from living list; leave → personal returns
- Do not invent scope: restore LWW join merge later (FU / backlog)

### RC36 — Guest/member DemoUI + session tests
- Status: done (this train)
- Paths: DemoUISupport (`-oneCartDemoRole member`), GuestMemberSessionTests, CloudKitBackendService.familyMembers fallback access
- What changed: separate demo state for participant on shared cart; unit tests for member access, no owner rename/revoke, return to personal; no-share metadata fallback uses `access(for:)` (member on shared)
- How to verify: `GuestMemberSessionTests`; sim `-oneCartDemoUI -oneCartDemoRole member -oneCartDemoTab account` → Leave, no Rename for member; owner still sees Revoke on private-store cart
- Do not invent scope: real CKShare participant list still requires CloudKit share record

### RC37 — Home & Lock Screen Widgets (Build 86)
- Status: done (this train)
- Paths: OneCartWidgets/, WidgetSnapshotStore, WidgetCartSnapshot, AppSession+Widget, ToggleProductPurchasedIntent
- What changed: Interactive Home & Lock Screen widgets (Small, Medium, Large, Circular, Inline, Rectangular), App Group snapshot sharing, theme synchronization with dark/light mode, optimistic interactive toggling from widget.
- How to verify: `WidgetSnapshotTests`, run widget extension in simulator.

### RC38 — Smart Family Push Notifications (Build 87)
- Status: done (this train)
- Paths: CartActivityNotifier.swift, CartActivityDiffTests.swift, AppSession+Hosts.swift, AppDelegate.swift, Localizable.xcstrings, docs/screenshots/
- What changed: Pure diff engine (`CartActivityDiff`) for detecting items added by partner and cart completed; anti-spam filters (self-actions ignored, baseline seeded on launch, single-user carts suppressed, multiple items coalesced); local banner and sound presentation via `UNUserNotificationCenter` in foreground and background; APNs remote notification registration in `AppDelegate`.
- How to verify: `CartActivityDiffTests` (8 unit tests), `just verify` (151 tests pass).

### RC39 — Quick Suggestion Chips (Build 88)
- Status: done (this train)
- Paths: CartSuggestionsEngine.swift, CartSuggestionsEngineTests.swift, ShoppingListView.swift, Localizable.xcstrings, docs/screenshots/
- What changed: `CartSuggestionsEngine` calculates top suggested items based on historical purchase frequency (`PurchaseHistoryEntity`) while excluding items currently in the cart and filtering dynamically by typed query (prefix-first); integrated horizontally scrollable suggestions inside the composer card cell in `ShoppingListView` with `.buttonStyle(.borderless)` for instant 1-tap additions; prevents tab-bar overlap and scroll desynchronization.
- How to verify: `CartSuggestionsEngineTests` (6 unit tests), `just verify` (151 tests pass), UI verified in simulator.

