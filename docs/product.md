# Product flow

## Positioning vs Apple Family

| Allowed | Forbidden |
|---------|-----------|
| Soft line “Made for families on Apple” / “Для семьи на Apple” | Claiming Family Sharing membership APIs |
| CloudKit + `CKShare` + system Share Sheet | Public join ACL (`publicPermission` permissive) |
| Private invite via Messages / AirDrop / Mail | “Share with entire Apple Family in one API call” |

**Missing Apple APIs (do not invent):** list Family members, verify two users share a Family, push share to whole Family.

Apple Family does **not** merge carts by itself — participants need an in-app `CKShare` invite.

## Technical invite path

```text
Create shared list → Create CKShare (publicPermission = .none)
  → System Share Sheet → Messages / AirDrop / Mail → Accept
```

Legacy `onecart://invite/...` tokens and the old invite endpoint are gone.

## User flow

1. Install → Welcome: Sign in with Apple + short onboarding copy (iCloud errors + Retry on the same screen).
2. After sign-in → **Cart** tab with one household cart (`isHouseholdDefault`). Thumb-zone **+** opens a name-only quick add (type → Add → next).
3. If iCloud already has a cart for this account, show that cart instead of creating a duplicate empty one when possible.
4. After cart create, warm-start a private `CKShare` invite URL in the background. **Invite** from the cart toolbar (`person.badge.plus`) or Settings → family sheet (system Share Sheet).
5. Invitee: SIWA → open share link → Accept in iCloud → **active cart is replaced** by the shared family cart (empty private starter archived; private items with content auto-merged into shared, then private archived). No merge sheet.

**Shell:** two tabs only — Cart + Settings. No Stores tab. Purchase history lives under Settings.

Up to four people share one list; changes sync via CloudKit.

**Cart line items are unique.** If several members add the same product (same name or catalog URL), the cart shows a separate row for each add — quantities are never merged/summed into one position.

## Account and profile

- **Session:** Sign in with Apple credentials in Keychain (local session / display name only).
- **Sync / share:** device iCloud (`CKContainer.accountStatus` must be `.available`). SIWA alone is not enough.
- No email/password forms.
- Display name, avatar, banner: **device-local** — not in CloudKit, not in migration.
- Private carts on disk are scoped by SIWA-derived `cachedForUserID`; shared-store carts stay visible to the iCloud participant.
- Welcome **Retry** soft-retries by default; local SQLite wipe only when Core Data itself failed.
- Sign out clears the SIWA Keychain session and returns to Welcome; it does **not** sign out of device iCloud.
- Post-welcome failures use a system alert (`OK`), not toast/banner chrome.

## Default cart identity

- Display: localized `cart.default_title` («Наши покупки» / «Наші покупки» / Our shopping)
- Identity: `isHouseholdDefault`
- Legacy names `"Наша семья"` / `"Наша группа"` migrated once to the flag
