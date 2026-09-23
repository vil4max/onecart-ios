# Project state — 2026-09-23 (after tf-1.7.0-1)

Snapshot for resuming work after a pause. Update it when the release or CI state changes.

**Release line frozen again since 2026-09-23** (owner decision) after the one-iteration unfreeze
that shipped `tf-1.7.0-1` ([backlog-1.7.0.md](../tasks/done/backlog-1.7.0.md)): no release step, tag
or release task starts until the owner unfreezes it. Feature development on `main` continues — two
developers work on this project, so commits from another session land on `main` at any time and
are expected.

**1.6.0:** approved in App Review (2026-09-23); `v1.6.0` marks the submitted commit `c8390cf`
(build 118).

**1.7.0:** `tf-1.7.0-1` on `403d909` (2026-09-23); the `TestFlight` workflow fast-forwarded
`testflight`, Xcode Cloud builds it — [releases/1.7.0.md](../operations/releases/1.7.0.md). It
carries the other developer's Live Activity and Siri work (REQ-WIDGET-040…060 and
REQ-SIRI-010…040 still proposed), the review fixes to it, and the backlog round.

**Next task:** none assigned to this line; after unfreezing, the owner picks one from
[Open items](#open-items) in a new session.

**Owner-only:** the `tf-1.7.0-1` device checks in its What to Test (tag annotation), confirming
that the new Support and Privacy Policy URLs ([release.md](../operations/release.md), App Store
metadata) went live with 1.6.0, and approving or amending the proposed REQ-WIDGET-040…060 and
REQ-SIRI-010…040. `CD_HistoryItem.CD_createdByName` is in the CloudKit Production schema
(2026-09-23).

## Product

| Item | State |
|---|---|
| App Store | **1.5.0 (114)** Ready for Distribution (seen 2026-09-22) — [releases/1.5.0.md](../operations/releases/1.5.0.md) |
| App Review | **1.6.0** approved 2026-09-23 (build 118, `v1.6.0` on `c8390cf`) — [releases/1.6.0.md](../operations/releases/1.6.0.md) |
| TestFlight | 1.7.0 round `tf-1.7.0-1` on `403d909` — [releases/1.7.0.md](../operations/releases/1.7.0.md) |
| Scope | Stability first: SIWA → one living cart → name-only add → Completed → History by day → invite from Settings ([product.md](../requirements/product.md)) |
| Version in repo | `MARKETING_VERSION` 1.7.0, build 1 ([backlog-1.7.0.md](../tasks/done/backlog-1.7.0.md)) (Xcode Cloud assigns uploaded build numbers) |
| Minimum OS | iOS 27.0, raised 2026-09-21 in every target configuration; devices below iOS 27 can no longer install or update |

## Delivery flow

Decision: [ADR 0003](../decisions/0003-ci-split.md). Runbook: [release.md](../operations/release.md).
Reusable description of the same scheme in agent-engineering-kit:
[`skills/ios-release/references/gated-ci-release.md`](https://github.com/vil4max/agent-engineering-kit/blob/main/skills/ios-release/references/gated-ci-release.md).

- `main`: work lands through PRs; GitHub Actions `Tests` runs on every PR and push.
- `testflight`: fast-forwarded by the `TestFlight` workflow on an annotated `tf-X.Y.Z-N` tag →
  Xcode Cloud "Internal TestFlight (verified main)" → TestFlight Friends and Family. A push to
  `main` builds nothing ([ADR 0004](../decisions/0004-tag-gated-testflight.md)).
- `v` tags mark the commit whose TestFlight build was submitted; they move nothing.
- `release`: frozen at `0985313` (tag `v1.2.1`); nothing moves it since ADR 0004. Its Xcode Cloud
  workflow "App Store candidate (release tag)" is unused, to be retired in App Store Connect.
- Current refs: `testflight` at `86bb72d` (1.5.1); tags `v1.2.0`, `v1.2.1`, `v1.5.0`,
  `tf-1.3.0-1`, `tf-1.5.0-1`, `tf-1.5.0-2`, `tf-1.5.1-1`.

## Repository hygiene

Rules in [AGENTS.md](../../AGENTS.md#ci-and-releases): branches and worktrees exist only while
work is in progress; permanent branches are `main`, `testflight`, `release`. Checked 2026-09-17:
one worktree, no stale local or remote branches, no stashes, no build artifacts in the tree.

## Work done 2026-09-16 … 09-17

| PR | Change |
|---|---|
| #29 | Tests move from Xcode Cloud to GitHub Actions (ad-hoc signing for Keychain tests); Xcode Cloud Test action removed |
| #30 | `promote-testflight` job, `release.yml`, `promote-release.sh`; Xcode Cloud switched to `testflight`, release workflow added |
| #31 | Branch rules, Xcode Cloud settings table, failure handling in ADR 0003 and AGENTS.md |
| #32 | Release requires a green `Tests` run for the exact tagged commit |
| #33 | No cancellation of `main` runs; cancelled runs handled by the release script |
| `4c956c1` | Widget switch handles iOS 27 `systemExtraLargePortrait` (archive warning removed) |
| #34 | Xcode Cloud workflows renamed by the commits they build |
| #35, #36 | 1.2.1 release notes, tag `v1.2.1`, submission record, branch hygiene rule |
| #37 | Git history privacy audit and rewrite plan; phone number removed from the runbook (rewrite itself blocked on owner) |

Session learnings were contributed to agent-engineering-kit (`cd9027c`, the reference above) and
to its spec-pyramid and agent-coordination shakedown experiment.

## Open items

1. Resolved 2026-09-23: 1.6.0 approved in App Review; `v1.6.0` on `c8390cf`.
2. After 1.6.0 is released, check that the App Store listing shows the new Support and Privacy
   Policy URLs.
3. Done 2026-09-23: the redesign follow-ups — thumbnail and strings removed in `6e7e93c`; History
   "added by" `677e7b6`; CloudKit participant seam `5b3ab04`
   ([backlog-1.7.0.md](../tasks/done/backlog-1.7.0.md)).
4. Git history privacy cleanup — [task brief](../tasks/git-history-privacy-cleanup.md), blocked on
   owner decisions (removal list, rewrite after App Review, revoke retired Supabase key).
5. Signed two-device CloudKit sharing and widget checks on iOS 27 devices (not covered by CI).
6. CI runs the Runtime's shared `Tests` workflow on the public-preview `xcode-27` image (Xcode
   27.0, iPhone 17 on iOS 27.0), the only GitHub-hosted label carrying the iOS 27 SDK the app now
   requires. Once a GA label ships Xcode 27, set the `IOS_RUNNER` and `IOS_DEVELOPER_DIR`
   repository variables to it, and treat preview withdrawal as a TestFlight outage — no `tf-`
   tag can pass without a green `Tests` run ([ADR 0003](../decisions/0003-ci-split.md), "Runner
   image risk"). The `#if compiler(>=6.4)` guard in `CartWidgetViews.swift` is removed.
7. SonarCloud Automatic Analysis is attached to PRs but not part of CI (Sonar in CI was declined);
   decide whether to keep the app.
8. Done 2026-09-23: FU13 (Swift 6 language mode since `6063ea1`; escape hatches isolated in
   `f53582b`) and FU14 (UI smoke suite `4f0be81`, MetricKit logging `aa03564` → `1479d7b`). FU06
   (`PersistenceController` `@unchecked Sendable`) stays open in
   [review-changelog.md](../engineering/review-changelog.md).
9. iPhone Duo support, not scheduled. The foldable device needs the layout checked in every pose,
   and SwiftUI offers `ArrangementView` for split and overlay presentations around the hinge and
   cameras. The `iPhone Duo` simulator device type is already present in the installed Xcode 27.0;
   Apple documents running it through DeviceHub with Xcode 27.1. Read before scoping:
   [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo),
   [ArrangementView](https://developer.apple.com/documentation/swiftui/arrangementview),
   [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo).
   Note: an `ArrangementView` holds content, not navigation — Apple advises against putting
   `NavigationSplitView` inside one, which matters for the cart and history screens.
   2026-09-23: layout preparation landed (`9318c38`: share and launch chrome sized to the scene);
   the check in every pose is blocked — no installed simulator runtime (26.5, 27.0, 27.2
   `24B5084k`) supports the device type (`simctl create` → `SimError 403`). Toolbar items were
   left without `Label` titles until a Duo runtime shows whether vertical bars need them. The
   27.2 runtime installed for the check can be removed on the owner's word.
10. Member removal matches a participant by record name or email only, while the members list
    also identifies by phone number: a member known only by phone is listed but cannot be removed
    ("participant not found"). Found in the 1.7.0 round (`ShareParticipantRules`); a behaviour
    change for a separate owner-approved fix, spec-first under REQ-SHARE-040.
11. Cart rows wrap names mid-word at accessibility text sizes (seen in the 1.7.0 L7 screenshots);
    not in any round yet.
12. The trip card's check control is 44 × 30 pt (owner decision 2026-09-23: three rows within the
    160 pt Live Activity height); revisit if Apple changes the height limit.
