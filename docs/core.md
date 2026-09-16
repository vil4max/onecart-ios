# OneCart Family — core

Status: approved, 2026-09-16. Details live in
[requirements/product.md](requirements/product.md) and
[decisions/](decisions/).

## Goal

One shared family cart and a single place to see every purchase: one person
adds, another shops, everyone follows synchronized progress and a history of
what the family actually bought.

## Language

| Term | Meaning |
|---|---|
| Family (`FamilySpace`) | People joined to one cart through a `CKShare` invite link |
| Cart | One durable living cart per family; never closes or is recreated |
| Item | A name plus state: to buy or Completed |
| Completed | Checked during the current trip; still on the living cart |
| History day | Items Completed before today, moved to History by purchase day when the app opens or returns to foreground |

## Priorities

1. P1 Sync — local edits save immediately and propagate through iCloud;
   offline changes wait for connectivity and CloudKit scheduling.
2. P2 Transparency — who added / who completed an item, without calls.
3. P3 Memory — History by day answers what the family bought.
4. P4 Stability first — ship the core loop (SIWA → one cart → name-only add →
   Completed → overnight History → invite/sync) before expanding surface area.

## Constraints

- C1 Apple-native: CloudKit + `CKShare` + Sign in with Apple; no third-party backend.
- C2 Family data stays on Apple infrastructure; no uploading family data.
- C3 Do not claim Apple Family Sharing APIs that do not exist.
- C4 iPhone only.
- C5 Dual identity: Sign in with Apple owns the local session; the device iCloud
  account owns sync and sharing. SIWA alone is not enough.

## Non-goals

Budget tracking, store-catalog price comparison, multi-list task management,
messaging, user-cleared History.

Deferred until P4 holds (not non-goals): price input, multi-cart UI (FU01),
store or catalog-first shopping.
