# Release (owner runbook)

Bundle ID `com.vil555tim.onecart` · Team `BTHRDS7254` · Container `iCloud.com.vil555tim.onecart`.

## Preflight (this branch)

Version: **1.2.1 (2)** — bump `CURRENT_PROJECT_VERSION` before each further upload of 1.2.1.

**Scope for this train:** stability of household cart + invite/sync. Stores tab, catalog-first add, and rich product forms are out of the main UX on purpose — see [product.md](product.md) § Priority / § Why we cut surface area. Do not block release on restoring those features.

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

## 2. CloudKit Production schema (required for TestFlight)

TestFlight / App Store talk to CloudKit **Production**. New Core Data entities are **not** created there automatically. Without a deploy you get:

`Cannot create new type CD_ShoppingList in production schema`

(and the app alert about mirroring / Partial Failure).

**Do this before relying on any TF build:**

1. Open [CloudKit Console](https://icloud.developer.apple.com/) → container `iCloud.com.vil555tim.onecart`.
2. Environment: **Development** → Schema → confirm record types exist (at least):  
   `CD_FamilySpace`, `CD_ShoppingList`, `CD_Product`, `CD_Store`, `CD_PurchaseHistory`, `CD_HistoryItem`  
   (plus CloudKit system types / indexes NSPersistentCloudKitContainer created).
3. If Development is empty or stale: run the app once from Xcode (Debug) signed into iCloud so the container initializes the Development schema.
4. **Deploy Schema Changes to Production** (Schema → Deploy… → Production).
5. Force-quit the TestFlight app, relaunch, retry invite/sync.

Until Production matches Development, sync/share on TF will keep failing even if the binary is fine.

**Agents / CI cannot perform Deploy.** There is no API to promote schema to Production (`cktool` only imports Development). The container admin must click Deploy in CloudKit Console. App builds can only detect the failure and show a clear alert.

## 3. Two-device checklist

Physical devices, different iCloud accounts (simulator is UI/local Core Data only):

1. Signed Debug build on A and B (version 1.2.1 / build ≥ 2). Production CloudKit schema deployed (§2).
2. On A: SIWA → empty household cart; add items (including offline). Failures show as a system alert (OK), not a toast/banner.
3. Go online → items remain; after a moment both devices can edit the same cart once shared (no persistent sync chrome in the UI).
4. Cart toolbar invite (or Settings → семья) → Invite → open iCloud share URL on B.
5. On B: SIWA → accept share → shared cart replaces empty private starter (or private content is auto-merged into shared, then private archived); edits sync both ways.
6. Same product name added by A and B → two separate cart rows (not summed).
7. Remove member on A → B loses access.
8. Relaunch offline: local data opens; queued changes upload when back online.

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
| Shared replaces private (merge/archive) | `testMergeFamilyContentCopiesProducts`, `testMergeFamilyContentRemapsStoresOntoDestination`, `testArchiveFamilySpaceHidesCartAndSoftDeletesChildren`, `FamilyCartMerge` |
| Claim unassigned private carts / skip shared | `testClaimUnassignedFamilySpacesStampsPrivateOnly` |
| Complete list → history + replacement list | `testCompleteListArchivesProductsCreatesHistoryAndReplacementList` |
| Toggle / move / update / catalog price refresh | `BusinessLogicTests` cart lifecycle cases |
| Deduplicate stable IDs / Core Data vs CK errors | `testDeduplicateStableIDsKeepsNewerProduct`, `testIsUserFacingCoreDataFailureIgnoresCloudKit` |
| Invite does not block forever on mirror | `FamilyInviteLinkBuilder`: brief wait + `share()` retry; outer `shareTimedOut` |
| Invite link warm-up after cart create | `AppSession.scheduleInviteLinkPreparation` / `preparedInviteLink` |
| Quick add is name-only | `QuickAddProductSheet` |

## 4. TestFlight

### Preferred: Xcode Cloud → TestFlight

Not local Archive. ADP includes 25 compute hours/month. No GitHub Actions / fastlane in this repo.

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

- Privacy Nutrition Labels: name, user ID, user content (lists), store geolocation — “App Functionality”, no tracking (`PrivacyInfo.xcprivacy` already in project).
- Screenshots: iPhone 6.7" / 6.5".
- Review notes: “Sign in with Apple required; family sharing via iCloud CKShare invite from the cart toolbar / Settings”.

## 6. Not needed for this pet project

Own server, Supabase, GitHub Actions, fastlane, email/password auth, multi-cart UX (code can hold multiple spaces; UI hides creating a second group).

## 7. Ongoing

- Watch CloudKit quotas (fine for ~4 people).
- After Core Data model changes → deploy schema to Production again.
- Ship via Xcode Cloud (or local Archive fallback).
