# Release (owner runbook)

Bundle ID `com.vil555tim.onecart` · Team `BTHRDS7254` · Container `iCloud.com.vil555tim.onecart`.

## Preflight (this branch)

Version: **1.4 (1)** — bump `CURRENT_PROJECT_VERSION` before each further upload of 1.4; reset to **1** when bumping `MARKETING_VERSION`.

**Scope for this train:** living family cart sync + invite/ACL + owner Delete cart. Three tabs (Корзина / История / Аккаунт), name-only add, share from «Аккаунт»; Stores/catalog UI, price and unit input, theme prefs are out on purpose — see [product.md](product.md). Do not block release on restoring those features.

On a Mac with Xcode:

```bash
brew bundle --file=Tooling/Brewfile
just doctor
just verify
```

Or explicitly:

```bash
just build
just test
```

Simulator is enough for UI + unit tests. Real family sync needs two physical devices (below).

## 1. Apple Developer

1. Attach iCloud container `iCloud.com.vil555tim.onecart`.
2. Enable **Sign in with Apple**, **iCloud (CloudKit)**, **Push Notifications**.
3. Recreate Development/Distribution profiles after capabilities.
4. Team in Xcode must match the project Team.
5. Entitlements (`CKSharingSupported`, SIWA, iCloud) are already in the project — unsigned Debug builds compile without App ID setup; signed install + real sync need the steps above.

## 2. CloudKit Production schema (required for TestFlight and Xcode Run)

TestFlight / App Store talk to CloudKit **Production**. OneCart also pins **Production** in both Debug and Release entitlements (`com.apple.developer.icloud-container-environment = Production`) so Xcode Run mirrors the same schema as TestFlight (Core Data + share keys stay aligned). The shared scheme **Launch** configuration is **Release** for the same reason; **Test** stays **Debug** for `@testable`.

New Core Data entities **and new attributes** are **not** created in Production automatically. Without a deploy you get:

`Cannot create new type CD_ShoppingList in production schema`

or (after model field adds):

`Cannot create or modify field 'CD_deletedAt' in record 'CD_Product' in production schema`

(and the app alert about mirroring / Partial Failure).

**Do this before relying on sync/share:**

1. Open [CloudKit Console](https://icloud.developer.apple.com/) → container `iCloud.com.vil555tim.onecart`.
2. Prefer Environment **Production** → Schema → confirm record types exist (at least):  
   `CD_FamilySpace`, `CD_ShoppingList`, `CD_Product`, `CD_Store`, `CD_PurchaseHistory`, `CD_HistoryItem`  
   and that soft-delete fields such as `CD_deletedAt` appear on those types.
3. If fields are missing: initialize them in **Development** (run once against Development, or add fields), then **Deploy Schema Changes → Production**.
4. Force-quit the app (Xcode or TestFlight), relaunch, retry invite/sync.

Until Production has the fields Core Data expects, sync/share will keep failing even if the binary is fine.

**Agents / CI cannot perform Deploy.** There is no API to promote schema to Production (`cktool` only imports Development). The container admin must click Deploy in CloudKit Console. App builds can only detect the failure and show a clear alert.

## 3. Two-device checklist

Physical devices, different iCloud accounts (simulator is UI/local Core Data only):

1. Signed Debug / TestFlight build on A and B (version 1.4 / build ≥ 1). Production CloudKit schema deployed (§2).
2. On A: SIWA → empty household cart; add items (including offline). Failures show as a system alert (OK).
3. Go online → items remain; share so both can edit. After remote changes, B can pull-to-refresh or reopen Корзина (nav may show «Updating…») and trolley counts should match.
4. Tab «Аккаунт» → «Поделиться корзиной» → Invite → open iCloud share URL on B.
5. On B: SIWA → accept share → shared cart replaces empty private starter (or private content is auto-merged into shared, then private archived); edits sync both ways (including checkboxes).
6. Same product name added by A and B → two separate cart rows (not summed).
7. Remove member on A → B loses access.
8. On A (owner): **Delete cart** → confirm → new empty cart; old invite link stops working; B falls back to a private cart with an alert; A can share again (new URL).
9. Relaunch offline: local data opens; queued changes upload when back online.

### Code-level verification (no devices)

Covered by unit tests / static path review when Xcode devices are unavailable:

| Checklist step | Code / test coverage |
|----------------|----------------------|
| Household + default list | `testCreatingFamilySpaceAlsoCreatesGeneralList` |
| Add product → same store as FamilySpace (CK graph) | `testAddProductLandsInSameStoreAsFamilyForCloudKitSync` |
| Add product visible after viewContext merge | `testAddProductVisibleAfterViewContextMerge` |
| Offline local persist | `testOfflineRepositorySaveSurvivesContextReset` |
| Private carts scoped per SIWA account | `testFamilyCacheIsScopedToAuthenticatedUser`, `testSharedCartVisibleAlongsideOwnPrivateCart` |
| Same product from several members = separate lines | `testSameNamedProductsStayAsSeparateCartLines` |
| Shared replaces private (merge/archive) | `testMergeFamilyContentCopiesProducts`, `testMergeFamilyContentRejectsSharedSource`, `testArchiveFamilySpaceHidesCartAndSoftDeletesChildren` (`FamilyCartMergeTests`) |
| Claim unassigned private carts / skip shared | `testClaimUnassignedFamilySpacesStampsPrivateOnly` |
| Complete purchased → history, cart keeps the rest | `testCompletePurchasedMovesOnlyCheckedItems`, `testCompletePurchasedWithoutChecksDoesNothing` (`PurchaseSessionTests`) |
| Toggle in trolley / edit / delete tombstone | `testTogglePurchasedSetsAndClearsBuyer`, `testUpdateProductRewritesFields`, `testDeletedProductIsKeptAsSyncTombstoneAndHiddenFromUI` (`CartItemsTests`) |
| Deduplicate stable IDs / Core Data vs CK errors | `testDeduplicateStableIDsKeepsNewerProduct`, `testIsUserFacingCoreDataFailureIgnoresCloudKit` |
| Invite does not block forever on mirror | `FamilyInviteLinkBuilder`: brief wait + `share()` retry; outer `shareTimedOut` |
| Invite link warm-up after cart create | `AppSession.scheduleInviteLinkPreparation` / `preparedInviteLink` |
| Hard cart sync / product snapshot reload | `CartSyncService`, `CloudKitProductReloadPolicy`, `testRefreshFromServerPicksUpToggledPurchasedState` |
| Permission deny on shared mutations | `DenyAllPermissionAuthorizer` + `CartAccessTests` |
| Owner delete cart recreates private family | `testDeleteCartRecreatesPrivateFamily` |
| Quick add/edit is name-only inline in cart | `ShoppingListView` composer / inline row edit |

## 4. TestFlight

### Preferred: Xcode Cloud → TestFlight

Not local Archive. ADP includes 25 compute hours/month. No GitHub Actions / fastlane in this repo (**NC09**: CI is Xcode Cloud; pre-merge GH Actions are intentionally out).

**Prerequisites:** shared scheme `OneCart` with Archive; ASC app record; CloudKit Production schema; no `ci_scripts` needed.

```bash
xcodebuild -project OneCart/OneCart.xcodeproj -describeAllArchivableProducts -json
```

**First-time (Xcode UI):** push `main` → open `OneCart/OneCart.xcodeproj` → Report navigator → Cloud → Get Started → product `OneCart` / team `BTHRDS7254` → grant repo access → commit generated `OneCart/OneCart.xcodeproj/xcshareddata/xcodecloud/manifest.json`.

**Target workflow** (App Store Connect → Xcode Cloud → Manage Workflows):

| Field | Value |
|-------|-------|
| Repo | `https://github.com/vil4engineering/OneCart.git` |
| Project | `OneCart/OneCart.xcodeproj` |
| Start condition | Branch changes → `main` |
| Action 1 | Test — iOS, scheme `OneCart`, required |
| Action 2 | Archive — iOS, scheme `OneCart` → TestFlight (internal) |
| Post | Internal TestFlight → group **Friends&Family** |

After green build: set next build number if ASC expects `1`; confirm family Apple IDs in Friends&Family; owner sends `CKShare` link after install.

TestFlight builds: 90 days. Xcode Cloud artifacts: 30 days.

Docs: [Configuring your first Xcode Cloud workflow](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow).

### Fallback: local Archive

Only if Xcode Cloud is unavailable: bump `CURRENT_PROJECT_VERSION` → Product → Archive (scheme `OneCart`, Release) → Distribute → App Store Connect → TestFlight.

## 5. Public App Store (optional)

- Privacy Nutrition Labels: name, user ID, user content (lists) — “App Functionality”, no tracking (`PrivacyInfo.xcprivacy`). No location / store locator in the shipping app.
- Screenshots: iPhone 6.7" / 6.5".
- Review notes: “Sign in with Apple required; family sharing via iCloud CKShare invite from Account; anyone with the invite link can edit until the owner deletes the cart or removes the member”.

## 6. Not needed for this pet project

Own server, Supabase, GitHub Actions, fastlane, email/password auth, multi-cart UX (code can hold multiple spaces; UI hides creating a second group).

## 7. Ongoing

- Watch CloudKit quotas (fine for ~4 people).
- After Core Data model changes → deploy schema to Production again.
- Ship via Xcode Cloud (or local Archive fallback).
