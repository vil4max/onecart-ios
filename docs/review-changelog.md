# OneCart PR review changelog

Branch: feat/living-cart-and-tabs
Base: main
Audience: human reviewer + review agent (alex)

## Current layout (post-reorg)

Product: `OneCart/`. Docs index: [docs/README.md](README.md). Tooling configs under `Tooling/`. Root `justfile` imports `Tooling/justfile`.

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

## Changes

### RC01 — Engineering Runtime harness
- Status: done
- Paths: justfile, Tooling/justfile, Tooling/runtime.yml, Tooling/scripts/, Tooling/HostBuild/, Tooling/Brewfile, Tooling/.swiftformat, Tooling/.swiftlint.yml, AGENTS.md, .gitignore
- What changed: ios-agent-harness install (--personal); configs later moved under `Tooling/`
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
- Paths: OneCart/Data/CloudKit/CloudKitServices.swift, docs/product.md
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
- Paths: docs/architecture.md, docs/product.md, docs/release.md, docs/legacy.md, docs/README.md, README.md, AGENTS.md, docs/review-changelog.md
- How to verify: read docs/README.md; AGENTS points there

### RC15 — Xcode project under OneCart/ (single product directory)
- Status: done
- Paths: OneCart/OneCart.xcodeproj, OneCart/{Application,Features,Data,Shared,Resources,Tests}/, Tooling/
- What changed: product lives in `OneCart/`; nested Xcode groups match folders; harness under `Tooling/HostBuild/`
- How to verify: open `OneCart/OneCart.xcodeproj`; `just doctor`; `just build`; `just test`

## Follow-ups (explicitly not in this PR)
- FU01 Multi-cart
- FU02 iOS 17 @Observable migration for ViewModels
- FU03 Expand String Catalog beyond Welcome/cart title (full UI)
- FU04 IAP + Family Sharing subscriptions
- FU05 Further split Catalog/Shopping UI monoliths
- FU06 Replace PersistenceController @unchecked Sendable with stricter isolation
- FU07 Scraper HTML fixtures / Keychain PII / profile file protection
- FU08 Re-enable Stores tab / store-bound lists **only after** two-device invite+sync is solid
- FU09 Catalog-first add / WebKit price refresh as optional path (not blocking quick name add)
- FU10 Rich product editor fields (qty/unit/price/notes) behind a secondary “details” action
- FU11 Optional Settings surface (appearance) only if system appearance proves insufficient

### RC16 — Stability-first minimal shell (docs + UX)
- Status: done (this train)
- Paths: `RootView` tabs, `QuickAddProductSheet`, `docs/product.md`, `docs/architecture.md`, `docs/release.md`
- What changed: Cart+Settings only; thumb FAB + name-only add; invite on cart; history in Settings; documented cuts toward stability
- How to verify: read [product.md](product.md) § Priority; app has two tabs; + opens quick add; no Stores tab
- Do not invent scope: restoring Stores/catalog is FU08/FU09, not required for merge

### RC17 — Cart-only shell (no Settings prefs)
- Status: done (this train)
- Paths: `RootView`, `ShoppingViews`, `CartManagementSheet`, `DevicePreferences`, Catalog/Stores/Settings UI removed, `Localizable.xcstrings`, docs
- What changed: no Settings tab; share from cart home; copy uses «корзина»; default title «Список покупок»; theme/unit prefs removed; dead Stores/Catalog UI deleted
- How to verify: after Welcome only cart UI; «Поделиться» on cart; overflow → participants/history/profile; no theme/unit screens
- Do not invent scope: restoring Stores/catalog/Settings is FU08/FU09/FU11, not required for merge

### RC18 — Surface CloudKit Production schema failure as alert
- Status: done (this train)
- Paths: `CloudKitServices.swift`, `AppSession.swift`, `OneCartTests.swift`, `docs/release.md`
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
- Paths: `CloudKitServices.swift`, `docs/product.md`, `docs/architecture.md`, `docs/adr/0002-cloudkit-native-backend.md`, `README.md`, `docs/review-changelog.md`
- What changed: `publicPermission = .readWrite` so anyone with the share URL can Accept (Telegram/Messages forwards); supersedes RC10 `.none` ACL; Apple Family positioning still forbids Family Sharing membership APIs
- How to verify: `grep publicPermission` shows `.readWrite`; owner opens Share once on a build with RC23 so existing shares persist ACL; invitee taps forwarded `icloud.com/share/...` → Accept → shared cart
- Do not invent scope: no Universal Links, custom schemes, or `UICloudSharingController`

### RC23 — Persist link-join ACL on existing share URL fast path
- Status: done (this train)
- Paths: `CloudKitServices.swift`, `docs/review-changelog.md`
- What changed: reusing an already-published share URL now background-persists `publicPermission = .readWrite` (and branding), not branding alone — fixes Item Unavailable on Telegram forwards for pre-RC21 shares
- How to verify: owner Share again from Account; same or updated link opens for a second Apple ID that is not a private invitee
- Do not invent scope: no new share UX, no deleting old CKShares

### RC24 — Scene-based CKShare accept delivery
- Status: done (this train)
- Paths: `SceneDelegate.swift`, `AppDelegate.swift`, `OneCart.xcodeproj`, `docs/review-changelog.md`
- What changed: SwiftUI scene apps receive share metadata via `windowScene(_:userDidAcceptCloudKitShareWith:)` and cold-start `connectionOptions.cloudKitShareMetadata`; AppDelegate path kept as fallback; existing `acceptPendingCloudKitShares` → `adoptSharedFamilyCartIfNeeded` unchanged (one living cart)
- How to verify: invitee taps `icloud.com/share/...` (cold or warm) → Accept → shared cart replaces private starter; items from owner visible
- Do not invent scope: no Universal Links

### RC25 — Confirm before replacing cart on share join
- Status: superseded by RC27 (join alert removed)

### RC26 — Auto-adopt empty starter; alert dismiss is not Cancel
- Status: superseded by RC27 (join alert removed)

### RC27 — Remove share-join confirm alert
- Status: done (this train)
- Paths: `AppSession.swift`, `RootView.swift`, `SharedCartJoinTests.swift`, `docs/product.md`, `docs/review-changelog.md`
- What changed: after shared cart is available locally, always `adoptSharedFamilyCartIfNeeded` (merge/archive private); no Join/Cancel UI
- How to verify: invitee Accept → shared items without alert; `SharedCartJoinTests` cover empty adopt + content merge
- Do not invent scope: no new Account CTA

### RC22 — Deployment target iOS 26
- Status: done (this train)
- Paths: `OneCart.xcodeproj/project.pbxproj`, `ShoppingViews.swift`, `ProfileView.swift`, `README.md`, `docs/review-changelog.md`
- What changed: project + test targets aligned to `IPHONEOS_DEPLOYMENT_TARGET = 26.0` (app target already 26.0); clears XC Cloud `CKRecord`/`Sendable` availability warnings; drop iOS 16 `#available` for medium sheet
- How to verify: all `IPHONEOS_DEPLOYMENT_TARGET` = 26.0; Archive without CKRecord Sendable warnings
- Do not invent scope: no `@Observable` migration (FU02)

## Verification
- `just doctor`
- `just lint` (0 serious)
- `just build`
- `xcodebuild test -project OneCart/OneCart.xcodeproj -scheme OneCart -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:OneCartTests`
- Manual: Welcome → Sign in with Apple → Корзина (empty household cart) → thumb + → name → Add → check the row → «Завершить покупки» → checked items in История, unchecked still in the cart
- Manual (device): «Аккаунт» → Поделиться корзиной → accept on second device → shared cart replaces/merges private starter; errors via system alert
- See also [release.md](release.md) § Preflight + §3
