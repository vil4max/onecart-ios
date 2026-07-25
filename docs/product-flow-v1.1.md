# Product flow v1.1

## Positioning vs platform

| Allowed | Forbidden |
|---------|-----------|
| Soft line “Made for families on Apple” / “Для семьи на Apple” | Claiming Family Sharing membership APIs |
| Audience: Just me / With partner / With family | Fake “we found your Family members” |
| CloudKit + `CKShare` + system Share Sheet | Public join ACL (`publicPermission` permissive) |
| Private invite via Messages / AirDrop / Mail | “Share with entire Apple Family in one API call” |

**Missing Apple APIs (do not invent):** list Family members, verify two users share a Family, push share to whole Family.

## Technical invite path

```text
Create shared list → Create CKShare (publicPermission = .none)
  → System Share Sheet → Messages / AirDrop / Mail → Accept
```

## User flow

1. Install → Welcome (Sign in with Apple)
2. **Who will use OneCart?** — Just me / With partner / With family
3. Ensure one default cart titled **«Наши покупки»** / localized (`isHouseholdDefault`)
4. Partner / family choices open share / invite
5. If private + shared carts conflict → merge sheet
6. Empty household-default private starters may auto-drop (flag-based, not by display name)

## Default cart identity

- Display: localized `cart.default_title` («Наши покупки» / «Наші покупки» / Our shopping)
- Identity: `isHouseholdDefault`
- Legacy names `"Наша семья"` / `"Наша группа"` migrated once to the flag
