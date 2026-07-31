# Product

## Thesis

**OneCart** (user-facing **Tim's Cart**) is one shared family cart and a single place to see every purchase.

One person adds items, another shops, everyone sees progress live. Not chat threads about “buy more bread,” not screenshots of a list — a living shared state plus a history of what the family actually bought.

## Business skeleton

Four entities, one loop:

| Entity | Role |
|--------|------|
| **Family** (`FamilySpace`) | Up to four people via `CKShare` link-join (`publicPermission = .readWrite`); everyone can add and check items. Anyone with the invite URL can join and edit until the owner revokes the link or removes the member. The cart entity is durable — never deleted/recreated. |
| **Cart** | One per family; lives forever; never “closes” |
| **Item** | A name plus state: still needed, or **Completed** (checked) |
| **History day** | Purchases grouped by the calendar day they were marked completed |

```text
Family → living cart → items (to buy / Completed)
                         ↓ next calendar day, on app open / foreground
                    history by day
```

### Completed vs History

The cart mirrors the shopping trip:

1. Family adds name-only items to the shared cart.
2. Shopper checks items as they pick them — they move to **Completed** (strikethrough), still on the living cart.
3. Everyone sees Completed updates live over CloudKit.
4. There is **no** manual «Finish shopping» / Done CTA. When the app opens or returns to foreground on a **later calendar day**, items Completed before the start of today move into **History**, grouped by purchase day.
5. Completed items cannot be swipe-deleted; uncheck first if the mark was a mistake. To-buy items can still be deleted.

Checkbox means **Completed for this trip**, not yet archived. History is the overnight (calendar-day) archive.

### Product promises

1. **Sync** — added at home, visible in the store at once.
2. **Transparency** — who added / who completed an item, without calls.
3. **Memory** — History by day answers what the family bought.

Money is not a promise on this train: items are **name-only**. Price fields may exist in Core Data for sync/legacy, but there is no price UI or input.

### What OneCart is not

Not a budget tracker, not store-catalog price comparison, not a multi-list task manager, not a messenger. Those paths grew the CloudKit graph and blurred the core loop — leftover APIs and UI for them were removed.

## Shell

Three tabs after Welcome:

| Tab | Contents |
|-----|----------|
| **Корзина** | Living list; To Buy grouped by Metro category sections; Completed stays a flat list; `+` FAB overlays the list (inline name row + keyboard); Metro-style category icon; pull-to-refresh / appear hard sync; nav may show «Updating…» |
| **История** | Days (newest first); tap a day for its products; read-only (no delete); small caption explains overnight archive; last 30 history sessions + show more |
| **Аккаунт** | Participants, share cart (owner and members), rename cart / revoke invite (owner), leave (member), sign out |

Share is a secondary action in **Аккаунт**, not a primary cart CTA. Any cart member can open «Поделиться корзиной» and forward the same invite link. Owner **Revoke invite** closes the door for new joins (existing members stay); **Share** again reopens joining on the same durable cart.

Nav title is the cart name — fixed brand default `Tim's Cart` when the household cart is created (not derived from the owner's SIWA display name).

## User flow

1. Install → Welcome: Sign in with Apple + short cart pitch + iCloud errors / Retry.
2. After sign-in → one household cart (`isHouseholdDefault`). Tap `+` for an empty cart row with keyboard, type a name, keyboard Done to save.
3. Prefer an existing iCloud cart for this account over creating a duplicate empty one.
4. Check items into **Completed**; they stay on the living cart until the next calendar day, then move to **History** on app open / foreground.
5. After cart create, warm-start a private `CKShare` in the background. Invite from **Аккаунт**.
6. Invitee: SIWA → open share → Accept in iCloud → active cart becomes the shared family cart. Personal `FamilySpace` stays on disk (hidden); non-empty personal lines merge into shared with LWW by normalized name + newer `updatedAt`. No join alert.

Up to four people share one cart; changes sync via CloudKit.

**Identical cart lines merge (LWW).** Same `Product.id` within one cart, or same normalized name on join: keep one row; field values from the newer `updatedAt`. Quantities are not summed.

## Technical invite path

```text
Create household cart → warm-start CKShare (publicPermission = .readWrite)
  → Аккаунт → «Поделиться корзиной» → system Share Sheet → Accept
```

Anyone with the share URL can join and **edit** (Messages, Telegram, Mail, and forwards). Owner **Account → Revoke invite** sets `publicPermission = .none` (no new joins; members stay). Remove member kicks one person back to their durable personal cart. Legacy `onecart://invite/...` tokens are gone. Share creation has timeouts, `retryAfterSeconds` backoff when CloudKit asks, and a UI watchdog so the loader cannot stick.

## Account and profile

- **Session:** Sign in with Apple credentials in Keychain (local session / display name only).
- **Sync / share:** device iCloud (`CKContainer.accountStatus` must be `.available`). SIWA alone is not enough.
- Display name, avatar, banner: **device-local** — not in CloudKit. Set your cart nickname on **Account → Your name in the cart** (e.g. Папа / Мама). That name is stamped on items you add (`createdByName`) and when you mark them Completed (`purchasedByName`). Other members see those item attributions via sync; the Participants list still uses each person’s iCloud / SIWA identity when available, not your private nicknames for them.
- Private carts on disk are scoped by SIWA-derived `cachedForUserID`; shared-store carts stay visible to the iCloud participant.
- Sign out clears the SIWA Keychain session and returns to Welcome; it does **not** sign out of device iCloud.
- Owner **Revoke invite**: close door for new joins; cart UUID unchanged. No Recreate / delete-entity in UX.
- History is never user-cleared; retention/size optimization is a later backlog item.
- Failures use a system alert (`OK`), not toast/banner chrome.

## Default cart identity

- Personal cart default title: `cart.personal_title` from the user’s display name (fallback `cart.default_title` / Tim's Cart).
- Owner can rename the active cart (`FamilySpace.name`); invitees see that title.
- App display name / Welcome / share branding: **Tim's Cart** (module and bundle id remain `OneCart` / `com.vil555tim.onecart`).
- Identity flag: `isHouseholdDefault` on new household carts.
- JSON / rename-legacy-name import path was removed (pre–App Store); wipe app for a clean TestFlight start — see [legacy.md](legacy.md).
- Legacy starter names (`Shopping list`, `Список покупок`, «Наша семья», …) still migrate via `FamilyCartMerge`.

## Positioning vs Apple Family

| Allowed | Forbidden |
|---------|-----------|
| Soft line “Made for families on Apple” / “Для семьи на Apple” | Claiming Family Sharing membership APIs |
| CloudKit + `CKShare` + system Share Sheet | “Share with entire Apple Family in one API call” |
| Link-join invite (`publicPermission = .readWrite`) via Messages / Telegram / Mail / AirDrop | Listing Family members or verifying Family membership via missing Apple APIs |

**Missing Apple APIs (do not invent):** list Family members, verify two users share a Family, push share to whole Family.

Apple Family does **not** merge carts by itself — participants need an in-app `CKShare` invite.

## Stability context (engineering)

Ship a reliable SIWA → one cart → name-only add → Completed → overnight History → invite/sync loop before re-expanding surface area.

| Kept out of UX | Why |
|----------------|-----|
| Theme / unit prefs | System appearance; name-only add |
| Stores / catalog scrapers | Enlarged CK surface; blocked simple add |
| Rich product editor (qty / unit / price / notes) | Friction; add fields later on a working core |
| Multi-cart switcher / audience sheets | Deferred — see FU01; v1 keeps one active cart with durable hidden personal |
| Toast / sync banner chrome | Prefer system alert; cart nav shows short «Updating…» only while hard-refreshing |

Deferred until core is solid on real devices: multi-cart UI (personal + N invited, accent colors, move items — FU01 + Tasks & Ideas board), store locator as primary UX, catalog-first shopping, IAP / Family Sharing APIs, price input. History size/retention optimization without a Clear History button.

## Idea: history assistant (not this train)

History days are a dataset of family habits (what, how often, who). Possible later:

- Autocomplete while typing (“мол…” → “Молоко”)
- Reminders for regularly forgotten items
- Rough trip total once prices exist

Prefer on-device (including optional Foundation Models for category refine), no new cloud dependencies, no uploading family data. Prerequisite: stable core path first.


## Future: multi-cart UI (not this train)

Tracked as **FU01** and on [Tasks & Ideas](https://github.com/orgs/vil4engineering/projects/2) (App=OneCart).

Scope when greenlit:

- One durable **personal** cart + **N invited** shared carts visible in a switcher
- Personal accent color distinct from invited/family chrome
- Move items between personal and invited
- Account share/members bound to the **selected** cart
- App brand vs per-cart titles stay separate layers

v1 until then: one **active** cart on screen; personal `FamilySpace` remains on disk when joined to a shared cart.
