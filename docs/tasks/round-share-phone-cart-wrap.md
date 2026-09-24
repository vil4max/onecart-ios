# Task — round: remove phone-only members and keep whole words at accessibility sizes

Assignee: UI · OneCart (Claude Code session, 2026-09-24)
State: claimed
Requested by: SDLC Orchestrator relaying the owner's scope choice (2026-09-24); plan approved by the owner directly in this session the same day
Evidence: pending
Depends-on: none
Parallelism: up to 2
Profile: round
Plan hash: d70bb7505e92e9d8fba5526113a9635c8ba9e40fd39eff54c3137152befb959f

## Current status and authorization

Current outcome: package approved; requirements REQ-SHARE-040 (amended) and REQ-CART-130 (new) applied and locked; cards not started.

Authorized scope:

1. Scope choice (owner, in the SDLC Orchestrator session, 2026-09-24, relayed): backlog #10
   and #11 as OneCart's first `Profile: round`.
2. Requirements migration (owner, in this session, 2026-09-24): "B: headings (Recommended)" —
   landed as `0991e6a`.
3. Plan (owner, in this session, 2026-09-24): approved through plan mode.
4. Package approval (owner, in this session, 2026-09-24, AskUserQuestion "Утвердить package
   round (docs/tasks/round-share-phone-cart-wrap.md)?" with both requirement texts and the four
   cards quoted): "Утвердить package (Recommended)". The integrator applied both requirement
   texts with `Status: approved` in the round-opening commit, before `lock --write`.

Blocking decisions: none.
Permitted deviations: none.
Material assumptions: the phone number CloudKit returns in
`userIdentity.lookupInfo.phoneNumber` is the same raw string on both the members list and the
removal lookup, so the shared key needs no normalization; checked in (b) by reading both from
the same `CKShare.Participant`.
Next step: dispatch share-040-spec and cart-130-spec in parallel.
Out of scope: the "no longer in the share" wording, phone normalization, History row
wrapping, any release step or push of `main`.

## Scope

Backlog #10: a family member known to CloudKit only by phone number is listed in Settings
but cannot be removed, because the removal lookup (`ShareParticipantRules`) keys participants
by record name then email while the members list keys them by record name, email, then phone.
Backlog #11: at accessibility text sizes the cart row's category tile and check control grow
beside the name and leave it narrower than one word, so names break inside words.

In scope: the REQ-SHARE-040 amendment and new REQ-CART-130, their tests, one shared
participant key for the members list and the removal lookup, an accessibility-size layout
for `CartProductRow`. Not in scope: other screens, the error wording, History rows, releases.

## Acceptance

- Given a shared cart whose participants include one known only by phone number, when the
  owner removes that listed member, then the lookup returns that participant (REQ-SHARE-040).
- Given participants with record name, email or phone, when the members list builds a row and
  the removal lookup searches for that row's ID, then both use the same key, record name first
  (REQ-SHARE-040).
- Given the cart at accessibility sizes 1, 3 and 5, when a line is shown, then the name column
  spans the row's content width, and «Апельсиновый» fits on one line at accessibility sizes 1
  and 3 (REQ-CART-130).
- Given the cart at the default size, then the row layout is unchanged (REQ-CART-130).

## Constraints

iPhone only; iOS 27.0 deployment target and the Xcode 27.0 SDK used by CI. No new
dependencies. Swift 6 language mode. No CloudKit schema change. Writers do not use the
simulator. The release line stays frozen: no version bump, tag or push of `main` in this round.

## Requirements in the package

- REQ-SHARE-040 amendment, appended to its statement: "The member to remove is found by the
  same identity the members list shows: iCloud record name, then email, then phone number, so
  every listed member other than the owner can be removed."
- REQ-CART-130 — Whole words at accessibility text sizes (new): "When the text size is an
  accessibility size, the cart row gives the item name the full width of the row, with the
  category tile and the check control beside each other above or below it, so a word of the
  name breaks across lines only when the word alone is wider than the row."

## Cards

#### Card: share-040-spec — phone-only member test and requirement text

model: claude-sonnet-5
effort: medium
product question: n/a — spec and test only, nothing user-facing
metric: n/a — spec and test only, nothing user-facing
threshold: n/a — spec and test only, nothing user-facing
user-visible: none
Requirements: REQ-SHARE-040

#### share-040-spec dispatch — requirement text and failing test (2026-09-24)

Objective: Add `lookupPhoneNumber` to `ShareParticipantHandle`, its
`CKShare.Participant` conformance (`userIdentity.lookupInfo?.phoneNumber`) and the test fake,
and add the Swift Testing case "REQ-SHARE-040: a member known only by phone resolves to that
participant" wrapped in `withKnownIssue`, so it records today's defect while `just verify`
stays green.

Sources: REQ-SHARE-040; KIT-D-005

Intended deviations: none

Boundaries: owns `OneCart/Data/CloudKit/CloudKitShareSupport.swift` (protocol and conformance only),
`docs/requirements/product.md` (the REQ-SHARE-040 Coverage row only; the requirement text is
already applied and locked),
`OneCart/Tests/ShareParticipantRulesTests.swift`. Do not change the lookup logic. Stop after
one commit with `just verify` passing.

Output: writer report (READY or BLOCKED, branch, head SHA, steps with SHAs, gate results,
Conflicts found, unfinished steps, open problems) returned to the integrator.

#### Card: share-040-fix — one participant key for the members list and removal

model: claude-sonnet-5
effort: medium
product question: Can the owner remove every member the Settings list shows?
metric: identity kinds (record name, email, phone) whose listed member resolves to its participant in tests
threshold: 3 of 3, with record name winning over email and phone
user-visible: An owner can remove a family member who joined with a phone number.
Requirements: REQ-SHARE-040

#### share-040-fix dispatch — shared participant key (2026-09-24)

Objective: Introduce one participant key function (record name, then email, then phone) and
use it both where `CloudKitBackendService.familyMembers` builds `ShareParticipantSummary` and
in `ShareParticipantRules.participant(forMemberID:in:)`; remove `withKnownIssue` from the
phone test; add a case that the record name wins over email and phone.

Sources: REQ-SHARE-040; KIT-D-005

Intended deviations: none

Boundaries: owns `OneCart/Data/CloudKit/CloudKitShareSupport.swift`,
`OneCart/Data/CloudKit/CloudKitBackendService.swift` (the key expression in `familyMembers`
only), `OneCart/Tests/ShareParticipantRulesTests.swift`. No change to error types or strings.
Stop after one commit with `just verify` passing.

Output: writer report as for share-040-spec, ending with Conflicts found.

#### Card: cart-130-spec — accessibility-size row test and requirement text

model: claude-sonnet-5
effort: medium
product question: n/a — spec and test only, nothing user-facing
metric: n/a — spec and test only, nothing user-facing
threshold: n/a — spec and test only, nothing user-facing
user-visible: none
Requirements: REQ-CART-130

#### cart-130-spec dispatch — requirement text and failing hosted test (2026-09-24)

Objective: Add the REQ-CART-130 Coverage row in `docs/requirements/product.md` (the
requirement text is already applied and locked) and a hosted Swift Testing case in
`HostedCartViewTests` (pattern: the REQ-WIDGET-040 accessibility test) over `.large`,
`.accessibility1`, `.accessibility3`, `.accessibility5`: at accessibility sizes the
`cart.product_name` frame spans the row's content width, and «Апельсиновый» measured with the
body font at that size fits that width at accessibility sizes 1 and 3; at `.large` the layout
is the current one. Wrap the accessibility-size assertions in `withKnownIssue`.

Sources: REQ-CART-130; KIT-D-005

Intended deviations: none

Boundaries: owns `docs/requirements/product.md` (the REQ-CART-130 Coverage row only), `OneCart/Tests/HostedViews/HostedCartViewTests.swift` and, if needed,
`OneCart/Tests/HostedViews/HostedView.swift`. No production code. Stop after one commit with
`just verify` passing.

Output: writer report as for share-040-spec, ending with Conflicts found.

#### Card: cart-130-fix — accessibility-size cart row layout

model: claude-sonnet-5
effort: medium
product question: Does the cart keep whole words at accessibility text sizes?
metric: name column width against the row's content width, and the width of «Апельсиновый» at the body font
threshold: column equals the row content width at accessibility sizes 1 to 5; the word fits at accessibility sizes 1 and 3
user-visible: At the largest text sizes, item names in the cart wrap between words instead of inside them.
Requirements: REQ-CART-130

#### cart-130-fix dispatch — row layout branch (2026-09-24)

Objective: In `CartProductRow`, read `@Environment(\.dynamicTypeSize)` and at
`isAccessibilitySize` put the category tile and the check control on one line with the name
at full width below, as `CartProgressHeader` does; keep the default layout unchanged; remove
`withKnownIssue` from the REQ-CART-130 test.

Sources: REQ-CART-130; KIT-D-005

Intended deviations: none

Boundaries: owns `OneCart/Features/Shopping/CartProductRow.swift` and the REQ-CART-130 test
in `OneCart/Tests/HostedViews/HostedCartViewTests.swift`. Keep accessibility identifiers,
swipe actions and the rename action. Stop after one commit with `just verify` passing.

Output: writer report as for share-040-spec, ending with Conflicts found.

## Writer steps

- [ ] share-040-spec: phone on the participant seam, known-issue test
- [ ] share-040-fix: shared participant key; phone test passes
- [ ] cart-130-spec: REQ-CART-130 coverage row, known-issue hosted test
- [ ] cart-130-fix: accessibility-size row layout; hosted test passes

## Deferred

| Requirement | Status | Reason | Backlog | Expiry |
|---|---|---|---|---|
| REQ-SHARE-040 | Deferred | device-only | [project-state open item 5](../planning/project-state.md#open-items) | 2026-11-30 |

The deferred part is the signed two-device CloudKit removal of a member who joined by phone.
Deferred approval: pending

## Reviews
