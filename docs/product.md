# Product flow

## Positioning vs Apple Family

| Allowed | Forbidden |
|---------|-----------|
| Soft line “Made for families on Apple” / “Для семьи на Apple” | Claiming Family Sharing membership APIs |
| Audience: Just me / With partner / With family | Fake “we found your Family members” |
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

1. Install → Welcome (Sign in with Apple) → iCloud connect (errors + Retry on the same screen).
2. **Who will use OneCart?** — Just me / With partner / With family.
3. Ensure one default cart titled **«Наши покупки»** / localized (`isHouseholdDefault`).
4. Partner / family choices open share / invite (Settings → Members → Invite).
5. Invitee: “I was invited” → SIWA → open link → Accept in iCloud.
6. If private + shared carts conflict → merge sheet (move items / use shared only / keep private).
7. Empty household-default private starters may auto-drop (flag-based, not by display name).

Up to four people share one list; changes sync via CloudKit.

## Account and profile

- Session: Sign in with Apple credentials in Keychain.
- Sync: requires iCloud on device (`CKContainer.accountStatus`). No email/password forms.
- Display name, avatar, banner: **device-local** — not in CloudKit, not in migration.

## Default cart identity

- Display: localized `cart.default_title` («Наши покупки» / «Наші покупки» / Our shopping)
- Identity: `isHouseholdDefault`
- Legacy names `"Наша семья"` / `"Наша группа"` migrated once to the flag
