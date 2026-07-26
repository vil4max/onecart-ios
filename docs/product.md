# Product flow

## Priority: stability first

OneCart ships a **narrow, reliable core** before optional surface area.

| Order | Goal |
|-------|------|
| 1 | Sign in, one household cart, add/check items, offline local save |
| 2 | Private `CKShare` invite that actually opens and syncs on two devices |
| 3 | Clear errors (system alert), no stuck spinners / flashing chrome |
| 4 | Only then: richer catalog, stores map, multi-list UX, polish features |

**Rule for agents and PRs:** do not re-expand UI scope until the core path above is green on real devices. Extra features that touch CloudKit graphs, WebKit scrapers, or multi-list routing have already caused fragile invite/sync and heavy screens — they wait.

## Why we cut surface area

| Cut from main UX | Why (stability) | Status |
|------------------|-----------------|--------|
| **Stores tab** | Second navigation root + store-bound lists multiplied empty states, catalog entry points, and CK relationship surface without helping “one shared cart”. | Removed from shell. Data model / `StoresView` may remain in tree; not in tabs. |
| **Official store catalogs in cart** | WebKit scrapers + price refresh are high-churn and block the simple “type a name” path. | Not linked from cart; quick add is name-only. |
| **Rich product editor** (qty / unit / category / price / notes on add) | More fields → more abandon / keyboard friction; defaults are enough for a working list. | `QuickAddProductSheet`: name → Add → next. |
| **History as a main tab** | Third tab competed with cart focus. | Sheet under Settings. |
| **Audience / merge sheets / multi-cart switcher** | Parallel onboarding paths made accept-share and “which cart is active?” unreliable. | One household cart; invite replaces/merges private starter. |
| **Toast / sync banner chrome** | Flashing top errors felt broken and raced with CloudKit events. | System alert (`OK`) only. |

Deferred (explicit non-goals until core is stable): multi-cart, store locator as primary UX, catalog-first shopping, IAP / Apple Family Sharing APIs, public join links.

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
Create household cart → warm-start CKShare (background, publicPermission = .none)
  → Cart toolbar / Settings → system Share Sheet → Accept
```

Legacy `onecart://invite/...` tokens and the old invite endpoint are gone.

Invite must not hard-block on `recordID` forever; share creation has timeouts and UI watchdog so the loader cannot stick.

## User flow

1. Install → Welcome: Sign in with Apple + short onboarding copy (iCloud errors + Retry on the same screen).
2. After sign-in → **Cart** tab with one household cart (`isHouseholdDefault`). Thumb-zone **+** opens a name-only quick add (type → Add → next).
3. If iCloud already has a cart for this account, show that cart instead of creating a duplicate empty one when possible.
4. After cart create, warm-start a private `CKShare` invite URL in the background. **Invite** from the cart toolbar (`person.badge.plus`) or Settings → family sheet (system Share Sheet).
5. Invitee: SIWA → open share link → Accept in iCloud → **active cart is replaced** by the shared family cart (empty private starter archived; private items with content auto-merged into shared, then private archived). No merge sheet.

**Shell:** three tabs — Cart + History + Settings. Settings keeps invite/members + sign out (no theme/unit/profile).

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
