# Product

Core: P1, P2, P3, P4, C1, C2, C3, C4, C5 — [core.md](../core.md)

The line above applies to every requirement in this document: it is the detail
layer for the whole core, so no requirement here stands outside those
priorities and constraints. Approval is per requirement: each `REQ-…` heading
carries its own `Status:` line.

## Thesis

**OneCart** (user-facing **OneCart Family**) is one shared family cart and a single place to see every purchase.

One person adds items, another shops, everyone follows synchronized progress. Not chat threads about “buy more bread,” not screenshots of a list — a living shared state plus a history of what the family actually bought.

## Requirement IDs

The `REQ-<AREA>-NNN` headings below name behavior the owner approved before the
IDs existed (recorded as `Status: approved` on the owner's word, 2026-09-21);
assigning an ID does not add, widen or reinterpret a requirement. Changing what
a labelled statement *means* — or retiring it — is still an owner decision and
needs owner approval, exactly as before the IDs existed. Areas are `AUTH`
(session and account), `CART` (living cart and items), `HIST` (History by day),
`SHARE` (invite, join, membership), `SYNC` (propagation and merge), `SHELL`
(tabs, titles, error surface), `WIDGET` (widgets and notifications) and `SIRI`
(Siri and Shortcuts, proposed 2026-09-22). Numbers
rise in tens so a later statement can be inserted without renumbering; a
retired ID is never reused.

Each requirement is a heading with its own `Status:` line, followed by its
statement; the statement ends at the next heading, so context prose sits before
a section's first requirement. The owner approved moving the statements from
inline labels to headings on 2026-09-24 without changing their wording; the
approved set is the one approved on 2026-09-21, and the Live Activity and Siri
requirements stay proposed.

A behavior carries one ID, placed at its canonical statement. Prose elsewhere
that summarizes the same behavior is left unlabelled rather than given a second
ID. Scope statements — non-goals, deferred work, the stability context and the
"not this train" ideas — carry no IDs, because they describe what is *not* built
and there is no behavior to test. Tests cite these IDs by name; see
[Coverage](#coverage).

## Business skeleton

Four entities, one loop: the family, its cart, the cart's items and History
days.

```text
Family → living cart → items (to buy / Completed)
                         ↓ next calendar day, on app open / foreground
                    history by day
```

### REQ-SHARE-010 — Family (`FamilySpace`)

Status: approved

People joined via `CKShare` link-join (`publicPermission = .readWrite`); everyone can add and check items. Anyone with the invite URL can join and edit until the owner revokes the link or removes the member. The cart entity is durable — never deleted/recreated.

### REQ-CART-010 — Cart

Status: approved

One per family; lives forever; never “closes”

### REQ-CART-020 — Item

Status: approved

A name plus state: still needed, or **Completed** (checked)

### REQ-HIST-010 — History day

Status: approved

Purchases grouped by the calendar day they were marked completed

### Completed vs History

The cart mirrors the shopping trip, in the order of the requirements below.
Checkbox means **Completed for this trip**, not yet archived. History is the
overnight (calendar-day) archive.

#### REQ-CART-030 — Name-only add

Status: approved

Family adds name-only items to the shared cart.

#### REQ-CART-040 — Checking an item

Status: approved

Shopper checks items as they pick them — they move to **Completed** (strikethrough), still on the living cart.

#### REQ-SYNC-030 — Completed propagation

Status: approved

Completed updates propagate through CloudKit when synchronization runs.

#### REQ-HIST-020 — Overnight archive

Status: approved

There is **no** manual «Finish shopping» / Done CTA. When the app opens or returns to foreground on a **later calendar day**, items Completed before the start of today move into **History**, grouped by purchase day.

#### REQ-CART-050 — No swipe-delete of Completed items

Status: approved

Completed items cannot be swipe-deleted; uncheck first if the mark was a mistake. To-buy items can still be deleted.

### Product promises

#### REQ-SYNC-010 — Sync

Status: approved

Local edits save immediately and propagate through iCloud; offline changes wait for connectivity and CloudKit scheduling.

#### REQ-SYNC-020 — Transparency

Status: approved

Who added / who completed an item, without calls.

#### REQ-HIST-030 — Memory

Status: approved

History by day answers what the family bought.

#### REQ-CART-060 — Name-only items, no money

Status: approved

Money is not a promise on this train: items are **name-only**. Price fields may exist in Core Data for sync/legacy, but there is no price UI or input.

### What OneCart is not

Not a budget tracker, not store-catalog price comparison, not a multi-list task manager, not a messenger. Those paths grew the CloudKit graph and blurred the core loop — leftover APIs and UI for them were removed.

## Shell

Three tabs after Welcome: **Корзина**, **История** and **Настройки**.

Nav title is the cart name. Personal cart starts as `cart.personal_title` from the nickname; after the owner renames the cart, the title no longer follows nickname changes. Shared cart title is owner-editable via Rename.

### REQ-SHELL-010 — Корзина tab

Status: approved

Living list; To Buy grouped by Metro category sections; Completed stays a flat list; `+` FAB overlays the list (inline name row + keyboard); Metro-style category icon; pull-to-refresh / appear hard sync; nav may show «Updating…»

### REQ-CART-130 — Whole words at accessibility text sizes

Status: approved

When the text size is an accessibility size, the cart row gives the item name the full width of the row, with the category tile and the check control beside each other above or below it, so a word of the name breaks across lines only when the word alone is wider than the row.

### REQ-SHELL-020 — История tab

Status: approved

Days (newest first); tap a day for its products; read-only (no delete); small caption explains overnight archive; last 30 history sessions + show more

### REQ-SHELL-030 — Настройки tab

Status: approved

One screen in three groups: **Корзина** (name, members, share, revoke or leave), **Оформление** (theme: one choice sets both the app icon and the accent color; one row opens the app's page in the system Settings for language, notifications and permissions), **Аккаунт** (name, Sign out keeps the iCloud cart, permanent CloudKit account deletion). Appearance and language follow the device; the app has no theme, accent or language picker (owner, 2026-09-22)

### REQ-SHELL-040 — Share is secondary

Status: approved

Share is a secondary action in **Настройки**, not a primary cart CTA.

### REQ-SHARE-110 — Any member can share

Status: approved

Any cart member can open «Поделиться корзиной» and forward the same invite link. Owner **Revoke invite** closes the door for new joins (existing members stay); **Share** again reopens joining on the same durable cart. **Remove** kicks a member (not a ban); **Leave** exits the guest (rejoin with an open link).

## User flow

The flow, in order: install and sign in (REQ-AUTH-010); one household cart
(REQ-CART-070), preferring an existing iCloud cart (REQ-CART-080); check items
into **Completed** — they stay on the living cart until the next calendar day,
then move to **History** on app open / foreground; invite preparation
(REQ-SHARE-080) and joining (REQ-SHARE-090).

Family members share one cart; changes sync via CloudKit.

### REQ-AUTH-010 — Welcome

Status: approved

Install → Welcome: Sign in with Apple + short cart pitch + iCloud errors / Retry.

### REQ-CART-070 — Household cart and add

Status: approved

After sign-in → one household cart (`isHouseholdDefault`). Tap `+` for an empty cart row with keyboard, type a name, keyboard Done to save.

### REQ-CART-080 — Prefer an existing iCloud cart

Status: approved

Prefer an existing iCloud cart for this account over creating a duplicate empty one.

### REQ-SHARE-080 — Background invite preparation

Status: approved

Background preparation reads an existing open invite only; it never creates a share or reopens a revoked link. Explicitly invite from **Настройки → Корзина**.

### REQ-SHARE-090 — Joining a shared cart

Status: approved

Invitee: SIWA → open share → Accept in iCloud → active cart becomes the shared family cart. Personal `FamilySpace` stays on disk but is hidden from the session list until Leave. **Join merge is deferred** (no private→shared product copy for now). No join alert.

### REQ-SYNC-040 — New-device import

Status: approved

A newly installed device may create a provisional personal cart while iCloud imports. When an older personal cart arrives for the same account, its list becomes active after local provisional products and history are copied by stable identifiers. The provisional source is retained. Selecting a shared cart also retains other shared families on disk; selection never deletes another family.

### REQ-HIST-040 — Purchases counted once

Status: approved

History and suggestion frequency count each `(family ID, item ID)` once, including when multiple devices independently archive the same purchase. Duplicate transport records may remain in CloudKit.

### REQ-CART-090 — Identical cart lines (same cart)

Status: approved

Same normalized name within one cart
(case/whitespace/diacritic-insensitive — «Молоко» = «молоко»): keep one row.
Adding an existing name returns the living row and reveals it instead of
creating a second line; concurrent adds from different devices (different
`Product.id`) merge first-writer-wins on sync. Same `Product.id` within one
cart: keep one row. Cross-cart join merge (private → shared LWW) is deferred
— accept switches to the shared cart only.

## Technical invite path

```text
Create household cart → Settings → «Поделиться корзиной»
  → create/reopen CKShare (publicPermission = .readWrite) → system Share Sheet → Accept
```

### REQ-SHARE-020 — Link-join edits

Status: approved

Anyone with the share URL can join and **edit** (Messages, Telegram, Mail, and forwards). Legacy `onecart://invite/...` tokens are gone.

### REQ-SHARE-030 — Share deadlines and backoff

Status: approved

Share creation and persistence have caller deadlines and `retryAfterSeconds` backoff when CloudKit asks. A deadline ends the wait; an underlying CloudKit operation can still finish later.

### Membership (no ban list)

Each action below states its effect and when the person can rejoin.

Do **not** wipe personal stores / `hardReset` to “fix” a stuck invite — use **Share** to reopen the door.

#### REQ-SHARE-040 — Remove member

Status: approved

Kick (`CKShare.removeParticipant`). Invite door unchanged. Rejoin: yes, while door is `.readWrite`. The member to remove is found by the same identity the members list shows: iCloud record name, then email, then phone number, so every listed member other than the owner can be removed.

#### REQ-SHARE-050 — Leave cart

Status: approved

Guest purges local shared zone; returns to personal cart. Rejoin: yes, with an open invite link.

#### REQ-SHARE-060 — Revoke invite

Status: approved

Closes door only (`publicPermission = .none`). Not a guest ban. Current members stay. Rejoin: no, until owner **Share** again.

#### REQ-SHARE-070 — Share

Status: approved

Must persist door `.readWrite` before handing out the URL (repairs a closed CloudKit invite door without wiping the cart). Rejoin: opens joining.

## Account and profile

- Owner **Revoke invite**: close door for new joins; cart UUID unchanged. No Recreate / delete-entity in UX.

### REQ-AUTH-020 — Session

Status: approved

Sign in with Apple credentials in Keychain (local session / display name only).

### REQ-AUTH-030 — Sync / share

Status: approved

Device iCloud (`CKContainer.accountStatus` must be `.available`). SIWA alone is not enough.

### REQ-AUTH-040 — Display name

Status: approved

Display name: the name Sign in with Apple provides, kept on the device and editable in **Настройки**. It is shared with the members of the active cart through a synced member profile (`MemberProfile`: one row per iCloud user per cart, in the cart's CloudKit zone, keyed by the CloudKit user record name). Each device writes its own profile on sign-in, when a cart becomes active or is joined, and whenever the name changes; repeats write nothing, the newest `updatedAt` wins, and older rows of the same user become tombstones. The cart members list names each participant from their profile, then their iCloud name, then a numbered label ("Member 2"); your own row shows your name. When Apple provides no name, the app asks once after sign-in what the family should call you (**Save** or **Not now**; **Not now** is remembered and never asks again). The same name appears on items you add (`createdByName`) / mark Completed (`purchasedByName`). Avatar and banner stay device-local.

### REQ-AUTH-050 — Private carts scoped to the user

Status: approved

Private carts on disk are scoped by SIWA-derived `cachedForUserID`; shared-store carts stay visible to the iCloud participant.

### REQ-AUTH-060 — Sign out

Status: approved

Sign out clears the SIWA Keychain session and returns to Welcome; it does **not** sign out of device iCloud. It also clears the widget snapshot and pending widget actions.

### REQ-AUTH-070 — Delete Account

Status: approved

Delete Account permanently deletes private CloudKit zones for this iCloud user, clears the SIWA Keychain session and local stores, and returns to Welcome. Owner deletion removes the shared family cart for members; a member leaves the shared cart first so others keep it.

### REQ-AUTH-080 — Failed cloud deletion

Status: approved

If cloud deletion fails, keep credentials and preserve local SQLite. Pending cloud deletion opens in local recovery mode without CloudKit mirroring; retry deletion to finish. Once cloud deletion is confirmed, failed local cleanup must finish before successful sign-out.

### REQ-HIST-050 — History is never user-cleared

Status: approved

History is never user-cleared; retention/size optimization is a later backlog item.

### REQ-SHELL-050 — System alert for failures

Status: approved

Failures use a system alert (`OK`), not toast/banner chrome.

## Widgets and notifications

### REQ-WIDGET-010 — Widget snapshot

Status: approved

Home and Lock Screen widgets display a compact snapshot, with up to six needed and two completed items; totals cover the full cart.

### REQ-WIDGET-020 — Widget purchase actions

Status: approved

Purchase actions run through the app session and persist to Core Data. Pending commands carry account/cart identity and an explicit purchased state; they are acknowledged only after a successful save and retried after startup, foreground or imported changes. CloudKit propagation still follows its normal schedule.

### REQ-WIDGET-030 — Family activity notifications

Status: approved

Family activity notifications are local notifications created when the app observes imported cart changes. They require notification permission and an opportunity for the app to observe those changes; delivery is not an instantaneous server-push guarantee.

### Shopping trip (Live Activity)

Proposed 2026-09-22: the owner asked for the feature; the wording below awaits owner approval.

#### REQ-WIDGET-040 — Starting a shopping trip

Status: proposed

The shopper starts a shopping trip from the cart's progress header («Я в магазине»). The control shows only on an editable cart with lines still to buy while Live Activities are allowed for OneCart; a refusal is a system alert. The trip is one Live Activity for the signed-in account and the active cart. The Lock Screen shows the cart title, «N из M куплено» with a progress bar, the first three to-buy lines with a check control, how many more lines remain, and a stop control. The Dynamic Island shows the remaining count (compact), a progress ring (minimal) and the title, progress, two lines and the stop control (expanded).

#### REQ-WIDGET-050 — The trip follows the cart

Status: proposed

The trip reads the same snapshot as the widgets and changes with it, skipping updates that change nothing. A check on the activity runs the widget purchase path (REQ-WIDGET-020). A relaunched app adopts its running trip and ends any extra one. The trip is local to the shopper's iPhone: it updates only when the app observes a change (C1: no push server), and it is not shown on other members' devices. Each start and update marks the card stale one hour later, so a card the app has not changed for an hour is shown as possibly out of date.

#### REQ-WIDGET-060 — Ending the trip

Status: proposed

The trip ends immediately when the shopper stops it (in the cart or on the activity), when the cart is emptied, when the active cart or account changes, and on sign out or account deletion. Once every line is checked it shows the all-bought state and is dismissed five minutes later. A trip the shopper swipes away on the Lock Screen is treated as ended. The system's own Live Activity limits (about eight hours) still apply.

## Siri and Shortcuts

Proposed 2026-09-22: the owner asked for the feature; the wording below awaits owner approval.

### REQ-SIRI-010 — Add by voice

Status: proposed

«Добавь в OneCart» asks what to add and adds name-only lines (REQ-CART-030, REQ-CART-060) to the list the cart screen shows. One request may carry several names separated by commas, semicolons, line breaks or the standalone words «и», «і» and "and" (whole words in any case, so a name that merely contains those letters stays whole); blanks are dropped and a repeated name is added once. A name already on the cart keeps its line (REQ-CART-090). Siri says what was added, what was already there and what could not be added; a name that fails does not stop the rest, and a failure is spoken, never queued as an alert in the app. A signed-out session, a read-only cart or an empty request is refused with a spoken reason. A cart still being set up is waited for; a local failure is reported as one, not as an iCloud problem.

### REQ-SIRI-020 — What is left

Status: proposed

«Что осталось в OneCart» reads the to-buy names in the order the cart screen shows them (its category sections, REQ-SHELL-010), at most five followed by how many more remain, or says that the cart is empty or everything is bought. It never changes the cart.

### REQ-SIRI-030 — Start a trip by voice

Status: proposed

«Я в магазине с OneCart» starts the shopping trip (REQ-WIDGET-040) without opening the app.

### REQ-SIRI-040 — App Shortcuts and startup

Status: proposed

The three actions are App Shortcuts with phrases in English, Russian and Ukrainian, and appear in the Shortcuts app. Every phrase names the app; "OneCart" is accepted as an alternative name for "OneCart Family". Siri may launch the app in the background, so a request finishes the app's startup first and follows the normal CloudKit schedule afterwards. A startup that fails is reported as the app being unavailable, never as a sign-in problem, and the next request runs it again; only the Welcome Retry may reset local data. A request waits for startup at most 10 seconds, then reports the app unavailable and changes nothing afterwards (no line is added and no trip starts) while startup goes on. Answers and refusals are spoken in the language of the request, with plural forms for counts; Russian and Ukrainian use the formal register.

## Default cart identity

- Identity flag: `isHouseholdDefault` on new household carts.
- JSON / rename-legacy-name import path was removed (pre–App Store); wipe app for a clean TestFlight start — see [legacy.md](../planning/legacy-migration.md).

### REQ-CART-100 — Personal cart title

Status: approved

Personal cart title starts as `cart.personal_title` from the nickname (fallback `cart.default_title` / OneCart Family). Changing nickname retitles only while the cart still has that auto title; after **Rename cart**, the title is independent.

### REQ-CART-110 — Rename cart

Status: approved

Owner can rename the active cart (`FamilySpace.name`) — personal or shared; invitees see the shared title.

### REQ-SHELL-060 — Branding

Status: approved

App display name / Welcome / share branding: **OneCart Family** (module and bundle id remain `OneCart` / `com.vil555tim.onecart`).

### REQ-CART-120 — Legacy starter names

Status: approved

Legacy starter names (`Shopping list`, `Список покупок`, «Наша семья», …) still migrate via `FamilyCartMerge`.

## Coverage

Which tests prove each requirement above. A row lists the suite and, inside it,
each covering test's name with its own `test_REQ_<AREA>_<NNN>_` prefix stripped —
the full XCTest name is that prefix plus the listed suffix. Swift Testing cases
carry the ID in their `@Test` display name instead. `none` means no test asserts
the requirement today; the note says what is missing rather than implying a gap
that a rename could close.

Renaming a test never changed an assertion: only the identifiers moved. Tests
outside this table keep their original names — the table covers the fragile-test
matrix in [engineering/architecture.md](../engineering/architecture.md) and the
core path from [core.md](../core.md), not every suite.

| REQ ID | Covering tests |
|--------|----------------|
| REQ-AUTH-010 | `AppleSignInTests` → `welcomeViewModelSignInWithTestAccountBootstrapsSession`; `FragileStoreLoadTests` → `failureCauseArmsOnlyForStoreLoadCodes`, `isUserFacingCoreDataFailureIgnoresCloudKit`, `postLoadCocoaSaveErrorDoesNotArmHardReset`, `retryWelcomeDoesNotWipeUnlessCoreDataFailure`, `shouldHardResetStoresOnlyForCoreDataWelcomeFailure`, `storeLoadFailureArmsHardResetAndRetryRecovers`, `wrappedLoadFailureWithNonEnglishDescriptionIsStoreLoadFailure` |
| REQ-AUTH-020 | `AppleSignInTests` → `credentialStateForNeverIssuedUserID`, `keychainAppleSignInCredentialStorePersistsCredential`, `keychainStoreFallsBackToUserDefaultsBackup` |
| REQ-AUTH-030 | `AccountDeletionTests` → `deleteAccount_whenICloudUnavailable_showsSpecificMessage`; `InviteLinkPreparerTests` → `offlineThrows` |
| REQ-AUTH-040 | `AppleSignInTests` → `appleSignInCredentialBuildsDisplayNameAndAccountID`; `ManagedObjectModelTests` → `memberProfileBelongsToTheCartWithOptionalFields`; `MemberProfileTests` → `@Test "a name change publishes one profile into the active cart, and repeats write nothing"`, `@Test "back-to-back refreshes publish in order and leave one profile row"`, `@Test "a member publishes the profile into the shared cart's store"`, `@Test "duplicate rows of one member resolve to the newest, and an upsert tombstones the rest"`, `@Test "clearing the name withdraws it from the profile so members fall back"`, `@Test "without an iCloud identity nothing is published"`, `@Test "a store written by the previous model opens with the member profile entity"`; `FamilyMemberNamingTests` → `@Test "a participant's shared profile name wins over the iCloud name"`, `@Test "without a profile the iCloud name is used, then a numbered label"`, `@Test "numbered labels are distinct and do not depend on the participant order"`, `@Test "the current user keeps the account name, also as the default owner or by record name"`, `@Test "the owner leads the list and marks exactly one current user"`; `MemberNamePromptTests` → `@Test "the prompt is presented while the session asks for a name"`, `@Test "Save sends the trimmed name and never a placeholder"`, `@Test "Not now declines, and a swipe-down counts as Not now"`, `@Test "the session asks for a name only while the resolved name is a placeholder"`, `@Test "Not now is remembered and the prompt never returns"`, `@Test "saving from the prompt sets the name and shares it with the cart"`, `@Test "the prompt shows the question, the field, Save and Not now"`, `@Test "a root signed in without a name asks after the ride, and Not now closes it"` |
| REQ-AUTH-050 | `CartAccessTests` → `familyCacheIsScopedToAuthenticatedUser`, `sharedCartVisibleAlongsideOwnPrivateCart`; `FamilyCartLifecycleTests` → `claimUnassignedFamilySpacesStampsPrivateOnly` |
| REQ-AUTH-060 | `WidgetSnapshotTests` → `signOut_clearsWidgetDataAndRejectsLateWidgetAction` |
| REQ-AUTH-070 | `AccountDeletionTests` → `deleteAccount_whenCloudSucceeds_removesDiskProduct`, `deleteAccount_whenCloudSucceeds_signsOutAndClearsLocalState`, `deleteAccount_whenMember_leavesSharedBeforeCloudDelete`; `WidgetSnapshotTests` → `deleteAccount_clearsWidgetSnapshotAndPendingPurchases` |
| REQ-AUTH-080 | `AccountDeletionTests` → `deleteAccount_afterConfirmedCloudDeletion_retriesLocalCleanupWithoutCloud`, `deleteAccount_whenCloudFailsAfterDestructiveRequestStarted_keepsMarkerWithoutMirroring`, `deleteAccount_whenCloudFails_keepsSignedInAndLocalState`, `deleteAccount_whenCloudFails_preservesUnsyncedDiskProduct`, `detachAccountStores_preservesFilesAndRejectsLoadUntilRecovery`, `load_whenCleanupPreviouslyFailed_finishesDeletionBeforeOpeningStores`; `FragileStoreLoadTests` → `diagnosticsSnapshotCreatedBeforeExplicitHardReset`, `loadFailureDoesNotDestroyStoreFiles`, `partialLoadFailureAllowsRetryInSameProcess` |
| REQ-CART-010 | `FamilyCartLifecycleTests` → `archiveFamilySpaceHidesCartAndSoftDeletesChildren` |
| REQ-CART-020 | `CartItemsTests` → `updateProductRewritesFields` |
| REQ-CART-030 | `CartItemsTests` → `addProductVisibleAfterViewContextMerge`, `invalidNamesAreRejected`; `OneCartSmokeUITests` (UI) → `test_REQ_CART_040_addedItemMarkedBoughtUpdatesProgress` |
| REQ-CART-040 | `CartItemsTests` → `togglePurchasedSetsAndClearsBuyer`; `OneCartSmokeUITests` (UI) → `test_REQ_CART_040_addedItemMarkedBoughtUpdatesProgress` |
| REQ-CART-050 | `CartItemsTests` → `deleteProductSkipsPurchasedItems` |
| REQ-CART-060 | `HostedCartViewTests` → `@Test "the cart and its composer show no price, and REQ-SHELL-040: no share control"`; `RequirementConstraintTests` → `@Test "a name-only add and a rename never carry a price into the cart"` |
| REQ-CART-070 | `HouseholdEnsureTests` → `ensureHouseholdCreatesCartWhenEmpty` |
| REQ-CART-080 | `HouseholdEnsureTests` → `ensureHouseholdNoOpWhenActiveFamilyExists` |
| REQ-CART-090 | `CartItemsTests` → `deduplicateProductsByNameKeepsFirstWriter`, `duplicateNameIsDetectedBeyondFiftyLiveRows`, `reAddAfterDeleteCreatesNewLine`, `renameIntoExistingNameMergesRows`, `sameNamedProductsReuseExistingCartLine`; `CartSuggestionsEngineTests` → `@Test "Excludes cart items with the same diacritic-insensitive normalization as cart dedupe"`; `FamilyCartMergeTests` → `mergeFamilyContentLWWSameNormalizedName` |
| REQ-CART-100 | `CartAccessTests` → `customCartNameStopsFollowingParticipantNickname`, `personalCartNameUsesAccountDisplayName`, `renamingParticipantUpdatesPersonalCartTitleWhileAutoNamed` |
| REQ-CART-110 | `CartAccessTests` → `renameActiveCartUpdatesFamilySpaceName`; `GuestMemberSessionTests` → `guestCannotRenameOrRevokeSharedCart` |
| REQ-CART-120 | `FamilyCartMergeTests` → `contentSummaryAndLegacyNameMigrationRules` |
| REQ-CART-130 | `HostedCartViewTests` → `@Test "REQ-CART-130: the name spans the row's content width at accessibility sizes, and the current layout at .large"` |
| REQ-HIST-010 | `PurchaseSessionTests` → `historyDayGroupsByPurchasedAt` |
| REQ-HIST-020 | `PurchaseSessionTests` → `archivePurchasedBeforeKeepsItemsPurchasedAtStartOfToday`, `archivePurchasedBeforeMovesOnlyStaleCheckedItems`, `archiveStalePurchasedIfNeededViaSession` |
| REQ-HIST-030 | `HistoryPaginationTests` → `fetchHistoryDefaultLimitIs30`, `loadMoreHistoryAppends` |
| REQ-HIST-040 | `CartSuggestionsEngineTests` → `@Test "Counts replicated purchases once per family when ranking suggestions"`; `PurchaseSessionTests` → `archiveRetryReusesExistingPurchaseAndArchivesOnlyNewItems`, `historyGroupsChooseSamePurchaseAcrossArchiveSessions`, `historyIdentityPreservesOtherFamiliesAndDistinctSameNamePurchases` |
| REQ-HIST-050 | `HostedHistoryViewTests` → `@Test "an opened day lists its items read-only with the archive footer"`; `RequirementConstraintTests` → `@Test "browsing History through its ViewModel never removes an entry; paging is the only call"` |
| REQ-SHARE-010 | `CartAccessTests` → `familyAccessAllowsSharedListEditing`, `selectivePermissionAuthorizerBlocksSharedUpdates` |
| REQ-SHARE-020 | `CloudKitErrorMappingTests` → `cloudKitFamilyInviteShareMessageContainsShareURL`; `ShareParticipantRulesTests` → `@Test "REQ-SHARE-020: read-only and unknown participants become read-write; the owner is left alone"`, `@Test "REQ-SHARE-020: participants who already edit report no change, so nothing is saved"`, `@Test "REQ-SHARE-020: a share with only its owner reports no change"`, `@Test "REQ-SHARE-020: the CloudKit owner participant goes through the same seam untouched"` |
| REQ-SHARE-030 | `AccountViewModelTests` → `finishedShareWatchdogDoesNotTimeOutNextShare`; `InviteLinkPreparerTests` → `deadline_cancellationReturnsWithoutWaitingForCallback`, `deadline_returnsBeforeUnresponsiveOperationAndIgnoresLateSuccess` |
| REQ-SHARE-040 | `AccountViewModelFakeTests` → `@Test "only the owner can remove a member, and never themselves"`, `@Test "removing a member forwards that member to the session"`, `@Test "the removal dialog is driven by the pending member and clears it on dismiss"`; `CloudKitBackendServiceTests` → `@Test "on a local-only store every share mutation reports the cart as not shared"`, `@Test "removing a member needs the cart's CKShare; without one nothing is kicked"`; `SessionMembershipTests` → `@Test "a guest cannot remove members"`, `@Test "removing a member is a CKShare kick; a cart without a share reports it and stays intact"`, `@Test "removing a member needs the network"`, `@Test "the owner cannot remove themself"`; `ShareParticipantRulesTests` → `@Test "REQ-SHARE-040: the member row resolves to the participant with the same record name"`, `@Test "REQ-SHARE-040: without a record name the lookup email identifies the participant"`, `@Test "REQ-SHARE-040: a member who already left, or a participant without identity, is not found"`, `@Test "REQ-SHARE-040: a member known only by phone resolves to that participant"` |
| REQ-SHARE-050 | `GuestMemberSessionTests` → `guestLeaveCartReturnsToPersonal`, `guestReturnsToPersonalWhenSharedGone` |
| REQ-SHARE-060 | `CartAccessTests` → `revokeInviteKeepsFamilySpaceIdentity`; `SharedCartJoinTests` → `applyReadWriteACLPreservesRevokedPublicPermission`, `revokeIsDoorCloseNotGuestBan` |
| REQ-SHARE-070 | `SharedCartJoinTests` → `applyReadWriteACLReopensDoorWhenRequested` |
| REQ-SHARE-080 | `InviteLinkPreparerTests` → `createInviteLinkAlwaysRefetches`, `warmUpFailureLeavesCacheNil`; `SharedCartJoinTests` → `backgroundInvitePreparation_keepsRevokedShareClosed` |
| REQ-SHARE-090 | `GuestMemberSessionTests` → `guestSessionActivatesSharedCartAsMember`; `HouseholdEnsureTests` → `ensureHouseholdAdoptsSharedWhileOnPrivate`; `SharedCartJoinTests` → `adoptSelectsSharedWithoutMergingPrivateContent`, `alreadyOnSharedStaysShared`, `emptyPrivateAutoAdoptsShared`, `ensureHouseholdAdoptsSharedEvenWhenPrivateActive`, `newlyJoinedSharedCartBecomesActiveOverCurrentSharedCart`, `privateContentIsNotMergedIntoSharedOnAdopt`, `reloadPrefersSharedOverStoredPrivate`, `reloadSwitchesToSharedWhenSharedAppearsLater` |
| REQ-SHARE-100 | `RequirementConstraintTests` → `@Test "membership runs on CKShare links and participants, never on an Apple Family roster"`, `@Test "the app sources import no Family framework and name no Family-roster API"` |
| REQ-SHARE-110 | `InviteLinkPreparerTests` → `memberCanCreateInviteLink` |
| REQ-SHELL-010 | `CartItemsTests` → `sortedProductsPutsNewestToBuyFirstThenCompleted` |
| REQ-SHELL-020 | `HistoryViewModelTests` → `@Test "an opened day sections its items by category in cart order and previews the names"`, `@Test "days are newest first and an opened day resolves to its live contents"`; `HostedHistoryViewTests` → `@Test "an empty History explains itself and offers no control"`, `@Test "days list newest first with the overnight caption, and nothing on the screen deletes"`; `OneCartSmokeUITests` (UI) → `test_REQ_SHELL_020_historyDayOpensItsItems` |
| REQ-SHELL-030 | `AccountViewModelTests` → `memberGatesEnableLeaveOnly`, `ownerGatesEnableRenameAndRevoke`, `selectAppIconPersistsAndForwards`; `DevicePreferencesTests` → `testAccentFollowsTheAppIconAtLaunch`, `testLanguageFollowsTheSystemAndKeepsAppleLanguages`, `testThemeFollowsTheDeviceAtLaunch`; `HostedAccountViewTests` → `@Test "the owner's Settings is one screen: cart, sharing, Apple account, appearance, deletion, about"`; `OneCartSmokeUITests` (UI) → `test_REQ_SHELL_030_settingsTabShowsSignOut` |
| REQ-SHELL-040 | `HostedAccountViewTests` → `@Test "Share is a secondary Settings action: it creates the invite link and waits for connectivity"`; `HostedCartViewTests` → `@Test "the cart and its composer show no price, and REQ-SHELL-040: no share control"` |
| REQ-SHELL-050 | `CloudKitErrorMappingTests` → `cloudKitUserFacingErrorDetectsNetworkFailure`, `cloudKitUserFacingErrorMapsAuthAndPermission`, `cloudKitUserFacingErrorReplacesOpaquePartialFailure` |
| REQ-SHELL-060 | `HostedWelcomeViewTests` → `@Test "Welcome greets with OneCart Family, the pitch and Sign in with Apple"`; `RequirementConstraintTests` → `@Test "the app presents itself as OneCart Family while the module and bundle id stay OneCart"` |
| REQ-SYNC-010 | `FragileSyncOutcomeTests` → `cartContentStorePublishesAfterReload`, `syncCartAppearFailureDoesNotPresentAlert`, `syncCartPullFailureSetsFailedState`, `syncCartSuccessSetsSynchronized` |
| REQ-SYNC-020 | `CartItemsTests` → `togglePurchasedSetsAndClearsBuyer`; `PurchaseSessionTests` → `test_REQ_SYNC_020_archiveKeepsWhoAddedAndWhoBought`; `HostedHistoryViewTests` → `@Test "REQ-SYNC-020: an archived item names who added it next to who bought it; no name, no caption"`; `ManagedObjectModelTests` → `test_REQ_SYNC_020_storeWithoutHistoryCreatorOpensWithCurrentModel` |
| REQ-SYNC-030 | `CartItemsTests` → `deletedProductIsKeptAsSyncTombstoneAndHiddenFromUI`; `SharedCartJoinTests` → `refreshFromServerPicksUpToggledPurchasedState` |
| REQ-SYNC-040 | `FamilyCartMergeTests` → `restoreKeepsStableIDsHistoryAndSourceGraphAcrossRetries`; `HouseholdEnsureTests` → `delayedPrivateImportPreservesLocalItemsAndSelectsExistingCart`, `ensureHouseholdSelectsNewestWithoutDeletingOtherSharedFamilies`, `partialImportAndPendingMutationsDeferPersonalSelection`, `provisionalAndRestoredChoicesSurviveRestartAndPersonalFallback`; `SharedCartJoinTests` → `acceptSelectsNewestSharedWithoutDeletingOtherFamilies`, `cloudReloadKeepsChosenSharedCartWhenAnotherSharedCartIsNewer` |
| REQ-WIDGET-010 | `WidgetSnapshotTests` → `emptyAndAllPurchasedHelpers`, `snapshotEncodingAndDecoding`, `toggleWithPartialSnapshot_preservesHiddenPurchasedCount` |
| REQ-WIDGET-020 | `WidgetSnapshotTests` → `pendingPurchases_afterStoreRecreation_preservesCommandsUntilIndividualAcknowledgement`, `performWidgetPurchase_savesRepositoryBeforeAcknowledging`, `start_withDurableWidgetCommand_appliesItWithoutForegroundTransition`, `widgetPurchase_forDifferentAccountOrFamily_isRejectedBeforeEnqueue`, `widgetPurchase_forTombstonedProduct_isAcknowledgedWithoutRestoringIt`, `widgetRetry_afterNewerAppMutation_doesNotRestoreOldPurchasedState` |
| REQ-WIDGET-030 | `CartActivityDiffTests` → `firstSnapshotSeedsWithoutNotify`, `partialCompletionDoesNotNotifyAllPurchased`, `partnerAddsSingleItemNotifies`, `partnerCompletesLastItemNotifiesAllPurchased`, `selfAddedItemDoesNotNotify`, `selfCompletesLastItemDoesNotNotify`, `singleUserCartDoesNotNotify`; `SharedCartJoinTests` → `firstSnapshotSeedsWithoutNotify`, `newMemberAfterBaselineNotifies` |
| REQ-WIDGET-040 | `ShoppingTripActivityTests` → `@Test "the trip shows the cart's progress and its first three lines to buy"`, `@Test "starting requests one activity for this account and cart"`, `@Test "a trip needs lines to buy, a signed-in cart and Live Activities turned on"`, `@Test "a refused start names its cause"`, `@Test "the cart offers the trip only when there is something to buy and it can run"`; `HostedCartViewTests` → `@Test "the progress header offers the shopping trip, starts it, then offers to end it"`, `@Test "the trip control sits beside the progress, and below it at accessibility text sizes"` |
| REQ-WIDGET-050 | `ShoppingTripActivityTests` → `@Test "the trip follows the cart and skips updates that change nothing"`, `@Test "a cart change while the trip is starting still reaches it"`, `@Test "the card is marked stale an hour after its last change"`, `@Test "a relaunched app adopts its running trip and ends leftovers"`, `@Test "a relaunched app adopts only the trip of the signed-in account and active cart"`; `WidgetSnapshotTests` → `purchaseFromTheTripReachesItAndFinishesIt`, `lockScreenCheck_updatesTheTripBeforeReturning` |
| REQ-WIDGET-060 | `ShoppingTripActivityTests` → `@Test "checking the last line shows the finished trip, then dismisses it"`, `@Test "stop on the finished trip dismisses it at once"`, `@Test "starting again while the finished trip is shown leaves one card"`, `@Test "another cart, another account or an emptied cart ends the trip at once"`, `@Test "the stop button ends the trip, and a Lock Screen dismissal is noticed"`, `@Test "a card swiped away is noticed without waiting for a cart change"`, `@Test "starting after the card was swiped away puts a new card up"`, `@Test "the cart control starts the trip, then stops it"`; `WidgetSnapshotTests` → `signOut_endsTheShoppingTrip`, `signOutWhileTheTripIsStarting_endsIt`, `launchWithoutSignedInAccount_endsTheLeftoverTrip`, `failedStartup_keepsTheRunningTrip` |
| REQ-SIRI-010 | `CartIntentTests` → `splitsSeveralNamesAndDropsBlanksAndRepeats`, `splitsOnStandaloneAndWordsInThreeLanguages`, `addsNameOnlyLinesAndKeepsExistingOnes`, `refusesAnEmptyRequestOrASignedOutSession`, `speaksWhatWasAddedAndWhatWasAlreadyThere`, `waitsForAHouseholdCartStillBeingSetUp`, `aLocalFailureIsNotBlamedOnICloud`, `aFailedNameIsReportedAndTheRestStillGoIn`, `aFailedAddQueuesNoAlertInTheApp` |
| REQ-SIRI-020 | `CartIntentTests` → `readsTheLinesStillToBuy`, `readsInTheOrderTheCartScreenShows`, `speaksAShortListOrTheCartState` |
| REQ-SIRI-030 | `CartIntentTests` → `startsTheShoppingTrip` |
| REQ-SIRI-040 | `CartIntentTests` → `aFailedStartIsReportedAndRetriedOnTheNextRequest`, `aStartWithoutAnAccountIsReportedAsSignedOut`, `stopsWaitingForAStartupThatTakesTooLong`, `aTripThatWouldStartAfterTheLimitDoesNotStart`, `everyPhraseIsTranslatedAndNamesTheApp`; `CartIntentSpeechTests` → `speaksRussianWithPluralCounts`, `speaksUkrainianWithPluralCounts`, `russianAndUkrainianSpeechUsesTheFormalRegister` |

Fragile-test matrix (`F1`–`F11`) to requirement: `F1`, `F3`, `F11` →
REQ-AUTH-080; `F2` → REQ-AUTH-010; `F4`, `F5`, `F8` → REQ-SYNC-010 and
REQ-SYNC-030; `F6` → REQ-SHARE-090; `F7` → REQ-SHARE-010; `F9` → REQ-HIST-030.
`F10` (new Application files reach the compiled Sources phase) is a build-stage
gate proved by the `test_sim` compile, not by a named test, so it cites no ID.

## Positioning vs Apple Family

| Allowed | Forbidden |
|---------|-----------|
| Soft line “Made for families on Apple” / “Для семьи на Apple” | Claiming Family Sharing membership APIs |
| CloudKit + `CKShare` + system Share Sheet | “Share with entire Apple Family in one API call” |
| Link-join invite (`publicPermission = .readWrite`) via Messages / Telegram / Mail / AirDrop | Listing Family members or verifying Family membership via missing Apple APIs |

Apple Family does **not** merge carts by itself — participants need an in-app `CKShare` invite.

### REQ-SHARE-100 — Missing Apple APIs (do not invent)

Status: approved

List Family members, verify two users share a Family, push share to whole Family.

## Stability context (engineering)

Ship a reliable SIWA → one cart → name-only add → Completed → overnight History → invite/sync loop before re-expanding surface area.

| Kept out of UX | Why |
|----------------|-----|
| Unit / price input | Name-only add |
| Stores / catalog scrapers | Enlarged CK surface; blocked simple add |
| Rich product editor (qty / unit / price / notes) | Friction; add fields later on a working core |
| Multi-cart switcher / audience sheets | Deferred — see FU01; v1 keeps one active cart with durable hidden personal |
| Toast / sync banner chrome | Prefer system alert; cart nav shows short «Updating…» only while hard-refreshing |

Deferred until core is solid on real devices: multi-cart UI (personal + N invited, move items — FU01 + Tasks & Ideas board), store locator as primary UX, catalog-first shopping, IAP / Family Sharing APIs, price input. History size/retention optimization without a Clear History button.

## Idea: history assistant (not this train)

History days are a dataset of family habits (what, how often, who). Possible later:

- Broader autocomplete beyond the existing history-based suggestion chips
- Reminders for regularly forgotten items
- Rough trip total once prices exist

Prefer on-device (including optional Foundation Models for category refine), no new cloud dependencies, no uploading family data. Prerequisite: stable core path first.


## Future: multi-cart UI (not this train)

Tracked as **FU01** and on [Tasks & Ideas](https://github.com/orgs/vil4labs/projects/2) (App=OneCart).

Scope when greenlit:

- One durable **personal** cart + **N invited** shared carts visible in a switcher
- Personal accent color distinct from invited/family chrome
- Move items between personal and invited
- Account share/members bound to the **selected** cart
- App brand vs per-cart titles stay separate layers

v1 until then: one **active** cart on screen; after Accept the shared cart is the only cart in the session list; personal stays on disk for Leave (join merge deferred).
