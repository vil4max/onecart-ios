# Release runbook

Bundle ID `com.vil555tim.onecart` · Team `BTHRDS7254` · Container `iCloud.com.vil555tim.onecart`.

## Versioning and preflight

Marketing versions use `MAJOR.MINOR.PATCH`, with all three components treated as integers. A feature release increments MINOR and resets PATCH to `0`; a fix-only release increments PATCH instead. Do not roll MAJOR without an explicit request. The app and widget extension share one marketing version and build number.
A new marketing version resets the local build number to **1**; subsequent builds
of that version must use a higher unused number. Confirm the actual uploaded build
number in Xcode Cloud / App Store Connect before selecting it for submission.

Release notes per version: [releases/](releases/). App Store Connect version availability, cloud
build status, and submission status must be checked in an authenticated session before publication.

**Scope:** living family cart sync, invite and ACL, owner Revoke invite (durable cart), Home and Lock Screen widgets, persistent sign-in across relaunch, appearance preferences, local family activity notifications, and quick suggestion chips. Three tabs (Корзина / История / Настройки), name-only add, share from «Настройки»; Stores/catalog UI, price and unit input are out on purpose; see [product.md](../requirements/product.md).

### Quick suggestion chips
- **1-Tap Add Suggestions:** Frequently purchased items appear directly below the text input inside the composer card when adding an item.
- **Dynamic Frequency Ranking:** Powered by `CartSuggestionsEngine`, ranking suggestions by purchase frequency from historical shopping sessions, automatically excluding items already in the cart.
- **Real-Time Text Filtering:** Suggestions filter as the user types with prefix-match priority.
- **Clean Inset-Grouped Layout:** Integrated into the composer row cell with `.buttonStyle(.borderless)` — no bottom overlay, no floating tab bar collision, and no drag jitter.
- **Screenshots:**
  - ![Integrated composer suggestions](../screenshots/suggestions_integrated.png)
  - ![Suggestions added in 1 tap](../screenshots/suggestions_chips_added.png)

### Family activity notifications
- **Item added by partner:** Local notification when the app observes newly imported items from a family member (*«Маша добавила «Сыр» в корзину»*).
- **All items purchased:** Local celebration notification when the app observes a partner completing the last remaining item (*«Всё куплено! 🎉»*).
- **Anti-spam:** Ignores self-actions, seeds baseline on first install, suppresses single-user carts, aggregates multiple items into one concise banner.
- **Screenshots:**
  - ![Item added notification](../screenshots/push_item_added.png)
  - ![All purchased notification](../screenshots/push_all_purchased.png)

On a Mac with Xcode, SwiftLint (`brew install swiftlint`) and the ios-dev Claude Code plugin:

```bash
ios-verify   # project checks, lint, build, unit and UI smoke tests
```

Without the plugin, run the scheme's tests in Xcode (Product > Test, scheme `OneCart`) or the
commands of the `Tests` workflow (`.github/workflows/tests.yml`).

Simulator is enough for UI + unit tests. Real family sync needs two physical devices (below).

## 1. Apple Developer

1. Attach iCloud container `iCloud.com.vil555tim.onecart`.
2. Enable **Sign in with Apple**, **iCloud (CloudKit)**, **Push Notifications**.
3. Recreate Development/Distribution profiles after capabilities.
4. Team in Xcode must match the project Team.
5. Entitlements (`CKSharingSupported`, SIWA, iCloud) are already in the project. Unsigned Debug builds compile without App ID setup; signed install + real sync need the steps above.

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
   and that soft-delete / attribution fields such as `CD_deletedAt`, `CD_createdByName`, and
   `CD_purchasedByName` appear on the types that use them (especially `CD_Product`).
   Since 1.7.0 `CD_HistoryItem` also carries `CD_createdByName` (who added an archived item);
   deploy it before tagging a TestFlight build that includes it.
3. If fields are missing: initialize them in **Development** (run once against Development, or add fields), then **Deploy Schema Changes → Production**.
4. Force-quit the app (Xcode or TestFlight), relaunch, retry invite/sync.

Until Production has the fields Core Data expects, sync/share will keep failing even if the binary is fine.

**CI cannot perform Deploy.** There is no API to promote schema to Production (`cktool` only imports Development). The container admin must click Deploy in CloudKit Console. App builds can only detect the failure and show a clear alert.

## 3. Two-device checklist

Physical devices, different iCloud accounts (simulator is UI/local Core Data only):

1. Signed Debug / TestFlight build on A and B (the candidate version/build under test). Production CloudKit schema deployed (§2).
2. On A: SIWA → empty household cart; add items (including offline). Failures show as a system alert (OK).
3. Go online → items remain; share so both can edit. After remote changes, B can pull-to-refresh or reopen Корзина (nav may show «Updating…») and Completed counts should match.
4. Tab «Настройки» → «Поделиться корзиной» → Invite → open iCloud share URL on B.
5. On B: SIWA → accept share → shared cart becomes the only active cart (personal stays on disk, hidden); edits sync both ways (including Completed checkboxes).
6. Same normalized product name added by A and B → one cart row after sync. Re-adding an existing name reveals the same row without changing its purchase state; concurrent duplicates keep the first writer.
7. Mark items Completed on A → visible on B; next calendar day, open/foreground on either device → yesterday’s Completed move to History by day (read-only).
8. Remove member on A → B loses access.
9. On A (owner): **Revoke invite** → confirm → same cart UUID; new joins blocked; B stays on shared cart; A can **Share** again to reopen joining.
10. Relaunch offline: local data opens; queued changes upload when back online.

### Audit regression checks on devices

- Join a second shared family; verify the first family remains available to its other members.
- Revoke an invite, rename/relaunch, and verify joining stays closed until explicit Share.
- Restore on a fresh device while adding local items before import; verify restored and provisional purchases remain intact.
- Archive the same completed item offline on both devices, reconnect, and verify history/suggestions count it once.
- Fail account deletion or local cleanup; verify no false success and that retry completes. Check owner and member paths separately.
- Tap a widget with the app terminated; verify the persistent cart changes, failure retries do not invert the item, full-cart counts remain correct, and sign-out clears snapshot/actions.
- Inspect both built bundles for `PrivacyInfo.xcprivacy` before upload.

Unit tests and simulator verification do not replace these signed-device CloudKit/widget checks.

### Code-level verification (no devices)

Covered by unit tests / static path review when Xcode devices are unavailable:

| Checklist step | Code / test coverage |
|----------------|----------------------|
| Household + default list | `testCreatingFamilySpaceAlsoCreatesGeneralList` |
| Add product → same store as FamilySpace (CK graph) | `testAddProductLandsInSameStoreAsFamilyForCloudKitSync` |
| Add product visible after viewContext merge | `testAddProductVisibleAfterViewContextMerge` |
| Offline local persist | `testOfflineRepositorySaveSurvivesContextReset` |
| Private carts scoped per SIWA account | `testFamilyCacheIsScopedToAuthenticatedUser`, `testSharedCartVisibleAlongsideOwnPrivateCart` |
| Same normalized product name reuses one line | `testSameNamedProductsReuseExistingCartLine`, `testDeduplicateProductsByNameKeepsFirstWriter` |
| Shared replaces private (no join merge) | `testEmptyPrivateAutoAdoptsShared`, `testPrivateContentIsNotMergedIntoSharedOnAdopt`, `testEnsureHouseholdAdoptsSharedEvenWhenPrivateActive` (`SharedCartJoinTests`) |
| Claim unassigned private carts / skip shared | `testClaimUnassignedFamilySpacesStampsPrivateOnly` |
| Complete purchased → history, cart keeps the rest | `testCompletePurchasedMovesOnlyCheckedItems`, `testCompletePurchasedWithoutChecksDoesNothing` (`PurchaseSessionTests`) |
| Overnight archive (yesterday Completed → History) | `testArchivePurchasedBeforeMovesOnlyStaleCheckedItems`, `testArchivePurchasedBeforeKeepsItemsPurchasedAtStartOfToday`, `testArchiveStalePurchasedIfNeededViaSession` (`PurchaseSessionTests`) |
| History UI groups by purchase day | `testHistoryDayGroupsByPurchasedAt`, `testHistoryDayFormattingTodayAndYesterday` (`PurchaseSessionTests`) |
| Completed items cannot be deleted | `testDeleteProductSkipsPurchasedItems` (`CartItemsTests`) |
| Newest cart lines first | `testSortedProductsPutsNewestToBuyFirstThenCompleted` (`CartItemsTests`) |
| Toggle Completed / edit / delete tombstone (to-buy only) | `testTogglePurchasedSetsAndClearsBuyer`, `testUpdateProductRewritesFields`, `testDeletedProductIsKeptAsSyncTombstoneAndHiddenFromUI` (`CartItemsTests`) |
| Deduplicate stable IDs / Core Data vs CK errors | `testDeduplicateStableIDsKeepsNewerProduct`, `testIsUserFacingCoreDataFailureIgnoresCloudKit` |
| Invite does not block forever on mirror | `FamilyInviteLinkBuilder`: brief wait + `share()` retry; outer `shareTimedOut` |
| Read-only invite warm-up; revoked links stay closed | `AppSession.scheduleInviteLinkPreparation` / `FamilyInviteLinkBuilder.existingInviteLink` |
| Hard cart sync / product snapshot reload | `CartSyncService`, `CloudKitProductReloadPolicy`, `testRefreshFromServerPicksUpToggledPurchasedState` |
| Permission deny on shared mutations | `DenyAllPermissionAuthorizer` + `CartAccessTests` |
| Owner revoke invite keeps family identity | `testRevokeInviteKeepsFamilySpaceIdentity` |
| Join adopt switches active to shared | `testEnsureHouseholdAdoptsSharedEvenWhenPrivateActive` |
| Guest / member session (shared active) | `GuestMemberSessionTests` |
| Quick add/edit is name-only inline in cart | `ShoppingListView` composer / inline row edit |

## 4. TestFlight

### Preferred: Xcode Cloud → TestFlight

Not local Archive. ADP includes 25 compute hours/month. Xcode Cloud only archives and uploads; tests run in GitHub Actions ([`tests.yml`](../../.github/workflows/tests.yml)). Xcode Cloud starts only from the `testflight` branch, which only the `TestFlight` workflow moves, on an annotated `tf-` tag — see [ADR 0004](../decisions/0004-tag-gated-testflight.md). A push to `main` builds nothing. No fastlane.

**Prerequisites:** shared scheme `OneCart` with Archive; ASC app record; CloudKit Production schema. `OneCart/ci_scripts/ci_post_clone.sh` writes `CI_BUILD_NUMBER` into `CURRENT_PROJECT_VERSION`.

```bash
xcodebuild -project OneCart/OneCart.xcodeproj -describeAllArchivableProducts -json
```

**First-time (Xcode UI):** push `main` → open `OneCart/OneCart.xcodeproj` → Report navigator → Cloud → Get Started → product `OneCart` / team `BTHRDS7254` → grant repo access → commit generated `OneCart/OneCart.xcodeproj/xcshareddata/xcodecloud/manifest.json`. After setup, the start condition must be the `testflight` branch only, never `main` (ADR 0003, ADR 0004).

**Target workflow** (App Store Connect → Xcode Cloud → Manage Workflows):

| Field | Value |
|-------|-------|
| Repo | `https://github.com/vil4max/onecart-ios.git` (the Xcode Cloud GitHub app needs access to this repository) |
| Project | `OneCart/OneCart.xcodeproj` |
| Workflows | "Internal TestFlight (verified main)" (exact branch `testflight`); exact settings in [ADR 0003](../decisions/0003-ci-split.md). "App Store candidate (release tag)" is deactivated (ADR 0004); the remaining workflow has distribution "App Store Connect" (Apple's "TestFlight and App Store") and Restrict Editing on, which an App Review build needs |
| Action | Archive (iOS), scheme `OneCart` → App Store Connect; no Test action |
| Post | Internal TestFlight → group **Friends and Family** |

**Request a TestFlight round** (rules: [ADR 0004](../decisions/0004-tag-gated-testflight.md)):

1. Push the commit to build as the head of its push to `main`, and wait for its `Tests` run.
2. `OneCart/ci_scripts/tf-check.sh` (or `OneCart/ci_scripts/tf-check.sh <commit>`). It is
   read-only, needs `gh` signed in to read the `Tests` run, blocks on anything the workflow
   would reject, and prints the tag commands with the next free `BUILD`.
3. Write the round's What to Test — observable pass/fail checks plus what was not verified —
   and run the two printed commands. Paste the same text into App Store Connect when the build
   appears.
4. The `TestFlight` workflow run ends with `testflight -> tf-X.Y.Z-N`; "did not move" means no
   build was requested.

Failure handling: a rejected tag must be deleted locally and remotely before retrying
(`git push origin :refs/tags/tf-X.Y.Z-N`); a `Tests` run that took longer than the workflow's
45-minute wait needs a manual rerun of `TestFlight` with the same tag, not a new tag; a tag on a
commit `testflight` already contains moves nothing, so rebuild it with Start Build on
`testflight` in App Store Connect. Tag the next round only after the previous Xcode Cloud build
has uploaded.

**Submit for App Review:** pick the tested TestFlight build of the version in App Store Connect,
then the maintainer marks its commit with an annotated `vX.Y.Z` tag. The tag moves nothing;
`TestFlight` checks that the commit had its own `tf-X.Y.Z-N` round. Never push `testflight` or
`release` by hand.

After green build: set next build number if ASC expects `1`; confirm family Apple IDs in Friends and Family; send the `CKShare` link after install.

TestFlight builds: 90 days. Xcode Cloud artifacts: 30 days.

Docs: [Configuring your first Xcode Cloud workflow](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow).

### Fallback: local Archive

Only if Xcode Cloud is unavailable: bump `CURRENT_PROJECT_VERSION` → Product → Archive (scheme `OneCart`, Release) → Distribute → App Store Connect → TestFlight.

## 5. Public App Store

### App Information

| Field | Value |
|-------|-------|
| Name | `OneCart Family` |
| Subtitle | `Shared family shopping cart` |
| Primary category | Shopping |
| Age rating | 4+ |
| Support URL | `https://github.com/vil4max/onecart-ios/issues` |
| Privacy Policy URL | `https://github.com/vil4max/onecart-ios/blob/main/docs/privacy.md` (English and Russian) |
| Price | Free |

### Version 1.0: English (U.S.)

**Promotional text**

> One shared cart for the family: add at home, see it in the store. Check items into the trolley and keep purchase history.

**Description**

> OneCart Family keeps one shared shopping cart in sync for your household.
>
> Add items at home and see updates while shopping. Everyone can follow the same living list without chat messages or screenshots.
>
> How it works
> • Add items quickly using only the product name
> • See who added or completed an item
> • Mark products Completed as they go into the trolley
> • Completed items move to History automatically the next day when the app opens
> • Browse a read-only purchase history grouped by day
> • Invite family members from Settings using an iCloud share link
>
> OneCart Family uses Sign in with Apple and iCloud to keep the household cart private and synchronized. Store prices, catalogs, budgeting, and messaging are intentionally not part of the app.

**Keywords**

```text
shopping,cart,grocery,list,family,shared,iCloud,household,history,trolley
```

**What to Test**

> Please verify Sign in with Apple, name-only item entry, shared cart updates, Completed items, overnight History, inviting from Settings, and Settings → Apple Account → Delete Account.

### App Review Information

- Sign-in required: **on**. Reviewers authenticate through the system Sign in with Apple sheet;
  there is no developer-issued username or password; explain this in Review notes.
- Contact: the developer contact in [privacy.md](../privacy.md) (phone kept in App Store Connect only).
- Review attachment: a physical-device recording (~21s, 1290×2796, **1.0 (84)**) kept outside
  this public repository because it shows an Apple Account name and photo. Upload in
  App Store Connect → App Review Information → Attachment. Shows Sign in with Apple, Settings with separate Session / Account
  deletion sections, Delete Account, and return to Welcome.

**Review notes**

> AUTHENTICATION
> This app uses Sign in with Apple. There is no email/password account or demo password. On a review device signed into an Apple ID with iCloud enabled, tap Sign in with Apple and complete the system sheet.
>
> CORE FLOW
> Add an item by name in Cart. Mark it Completed to show shopping progress. Items completed on a previous calendar day move to read-only History when the app opens or returns to the foreground. Invite another person from Settings → Share cart using the system iCloud share sheet.
>
> ACCOUNT DELETION
> Open Settings → Apple Account → Delete Account and confirm. Successful deletion removes the user's private CloudKit data, clears local app data and the Sign in with Apple session, and returns to Welcome. If the user owns the active shared cart, it is deleted for its members. If the user is a member, the user leaves that shared cart and the owner's cart remains.
>
> The attached physical-device recording demonstrates sign-in, navigation to Delete Account, confirmation, completed deletion, and return to Welcome.

### Privacy and media

- Privacy Nutrition Labels: name, user ID, user content (lists): App Functionality, linked to
  identity, no tracking (`PrivacyInfo.xcprivacy`). No location or store-locator data in the shipping app.
- Screenshots: Welcome, Cart, History, and Settings in English and Russian at the 6.9-inch size
  (1320 × 2868); App Store Connect scales them down for smaller iPhone displays. The current set
  and how it is captured are in [assets/store/README.md](../../assets/store/README.md).

## 6. Not needed for this app

Own server, Supabase, fastlane, email/password auth, multi-cart UX (code can hold multiple spaces; UI hides creating a second group).

## 7. Ongoing

- Watch CloudKit quotas (fine for household-sized carts).
- After Core Data model changes → deploy schema to Production again.
- Ship a TestFlight round with a `tf-` tag, submit one of its builds, then mark the commit with a `v` tag (or local Archive fallback).
