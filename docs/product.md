# Product

## Thesis

**OneCart is one shared family cart and a single place to see every purchase.**

One person adds items, another shops, everyone sees progress live. Not chat threads about “buy more bread,” not screenshots of a list — a living shared state plus a history of what the family actually bought.

## Business skeleton

Four entities, one loop:

| Entity | Role |
|--------|------|
| **Family** (`FamilySpace`) | Up to four people via `CKShare` link-join (`publicPermission = .readWrite`); everyone can add and check items |
| **Cart** | One per family; lives forever; never “closes” |
| **Item** | A name plus trolley state: still needed, or already in the physical cart |
| **Session** | Snapshot of what was paid for in one trip: when, who, how many items |

```text
Family → living cart → items (needed / in trolley)
                         ↓ «Завершить покупки»
                    purchase session → history
```

### Trolley metaphor

The app mirrors the store floor:

1. Family piles items into the shared cart.
2. Shopper walks the aisle, picks from the shelf into a real trolley, taps the checkbox.
3. Home sees “in the trolley” immediately over CloudKit.
4. At checkout, **Завершить покупки** moves checked items into history as bought; unchecked items stay for the next trip.

Checkbox means **in the trolley**, not paid. “Bought” happens at session complete.

### Product promises

1. **Sync** — added at home, visible in the store at once.
2. **Transparency** — who put what in the trolley, without calls.
3. **Memory** — sessions answer what the family buys regularly.

Money is not a promise on this train: items are **name-only**. Price fields may exist in Core Data for sync/legacy, but there is no price UI or input.

### What OneCart is not

Not a budget tracker, not store-catalog price comparison, not a multi-list task manager, not a messenger. Those paths grew the CloudKit graph and blurred the core loop — leftover APIs and UI for them were removed.

## Shell

Three tabs after Welcome:

| Tab | Contents |
|-----|----------|
| **Корзина** | Living list, trolley progress, `+` quick add (name only, medium sheet, dismiss after one add) |
| **История** | Purchase sessions (month sections, last 30 + show more) |
| **Аккаунт** | Participants, share cart (owner), sign out |

Share is a secondary action in **Аккаунт**, not a primary cart CTA. Invite once; shop every day.

Nav titles: `🛒 Моя корзина` when alone; `👨‍👩‍👧‍👦 Общая корзина` when `familyMembers.count >= 2`.

## User flow

1. Install → Welcome: Sign in with Apple + three-step trolley metaphor + iCloud errors / Retry.
2. After sign-in → one household cart (`isHouseholdDefault`). `+` opens name-only quick add.
3. Prefer an existing iCloud cart for this account over creating a duplicate empty one.
4. After cart create, warm-start a private `CKShare` in the background. Invite from **Аккаунт**.
5. Invitee: SIWA → open share → Accept in iCloud → active cart becomes the shared family cart (empty private starter archived; private items with content merged, then archived). No merge sheet.

Up to four people share one cart; changes sync via CloudKit.

**Cart lines are unique.** Same product name from several members stays as separate rows — quantities are never merged.

## Technical invite path

```text
Create household cart → warm-start CKShare (publicPermission = .readWrite)
  → Аккаунт → «Поделиться корзиной» → system Share Sheet → Accept
```

Anyone with the share URL can join (Messages, Telegram, Mail, and forwards). Legacy `onecart://invite/...` tokens are gone. Share creation has timeouts and a UI watchdog so the loader cannot stick.

## Account and profile

- **Session:** Sign in with Apple credentials in Keychain (local session / display name only).
- **Sync / share:** device iCloud (`CKContainer.accountStatus` must be `.available`). SIWA alone is not enough.
- Display name, avatar, banner: **device-local** — not in CloudKit.
- Private carts on disk are scoped by SIWA-derived `cachedForUserID`; shared-store carts stay visible to the iCloud participant.
- Sign out clears the SIWA Keychain session and returns to Welcome; it does **not** sign out of device iCloud.
- Failures use a system alert (`OK`), not toast/banner chrome.

## Default cart identity

- Nav display: `cart.mine_title` / `cart.shared_title` (computed from member count).
- Identity flag: `isHouseholdDefault`.
- Legacy names `"Наша семья"` / `"Наша группа"` / `"Наши покупки"` / `"Our shopping"` / `"Наші покупки"` migrated once to the flag.
- `cart.default_title` remains for legacy/tests.

## Positioning vs Apple Family

| Allowed | Forbidden |
|---------|-----------|
| Soft line “Made for families on Apple” / “Для семьи на Apple” | Claiming Family Sharing membership APIs |
| CloudKit + `CKShare` + system Share Sheet | “Share with entire Apple Family in one API call” |
| Link-join invite (`publicPermission = .readWrite`) via Messages / Telegram / Mail / AirDrop | Listing Family members or verifying Family membership via missing Apple APIs |

**Missing Apple APIs (do not invent):** list Family members, verify two users share a Family, push share to whole Family.

Apple Family does **not** merge carts by itself — participants need an in-app `CKShare` invite.

## Stability context (engineering)

Ship a reliable SIWA → one cart → add/check → invite/sync loop before re-expanding surface area.

| Kept out of UX | Why |
|----------------|-----|
| Theme / unit prefs | System appearance; name-only add |
| Stores / catalog scrapers | Enlarged CK surface; blocked simple add |
| Rich product editor (qty / unit / price / notes) | Friction; add fields later on a working core |
| Multi-cart switcher / audience sheets | Unreliable “which cart?” paths |
| Toast / sync banner chrome | Raced with CloudKit; system alert only |

Deferred until core is solid on real devices: multi-cart, store locator as primary UX, catalog-first shopping, IAP / Family Sharing APIs, public join links, price input.

## Idea: history assistant (not this train)

History sessions are a dataset of family habits (what, how often, who). Possible later:

- Autocomplete while typing (“мол…” → “Молоко”)
- Reminders for regularly forgotten items
- Sort cart by category / aisle
- Rough trip total once prices exist

Prefer on-device, no new cloud dependencies, no uploading family data. Prerequisite: stable core path first.
