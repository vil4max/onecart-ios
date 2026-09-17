# Project state — 2026-09-17

Snapshot for resuming work after a pause. Update it when the release or CI state changes.

## Product

| Item | State |
|---|---|
| App Store | 1.2 (91) live |
| In App Review | **1.2.1 (105)**, submitted 2026-09-17 10:13, auto-release after approval — [releases/1.2.1.md](../operations/releases/1.2.1.md) |
| Scope | Stability first: SIWA → one living cart → name-only add → Completed → History by day → invite from Settings ([product.md](../requirements/product.md)) |
| Version in repo | `MARKETING_VERSION` 1.2.1, build 1 (Xcode Cloud assigns uploaded build numbers) |

## Delivery flow

Decision: [ADR 0003](../decisions/0003-ci-split.md). Runbook: [release.md](../operations/release.md).
Reusable description of the same scheme in agent-engineering-kit:
[`skills/ios-release/references/gated-ci-release.md`](https://github.com/vil4max/agent-engineering-kit/blob/main/skills/ios-release/references/gated-ci-release.md).

- `main`: work lands through PRs; GitHub Actions `Tests` runs on every PR and push.
- `testflight`: fast-forwarded by CI after a green push to `main` → Xcode Cloud
  "Internal TestFlight (verified main)" → TestFlight Friends and Family.
- `release`: fast-forwarded by `Release` after an annotated `vX.Y.Z` tag whose commit has its own
  green `Tests` run → Xcode Cloud "App Store candidate (release tag)" → App Store Connect.
- Current refs: `testflight` and `release` at `a5e6915` (tag `v1.2.1`); tags `v1.2.0`, `v1.2.1`.

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

1. Watch App Review for 1.2.1; on rejection fix on `main`, bump PATCH, tag again.
2. Git history privacy cleanup — [task brief](../tasks/git-history-privacy-cleanup.md), blocked on
   owner decisions (removal list, rewrite after App Review, revoke retired Supabase key).
3. Signed two-device CloudKit sharing and widget checks on iOS 27 devices (not covered by CI).
4. CI pins Xcode 26.6 while local and Xcode Cloud use Xcode 27; bump the pin when the runner image
   offers Xcode 27 and remove the `#if compiler(>=6.4)` guard in `CartWidgetViews.swift`.
5. SonarCloud Automatic Analysis is attached to PRs but not part of CI (Sonar in CI was declined);
   decide whether to keep the app.
6. Follow-ups from [review-changelog.md](../engineering/review-changelog.md) (FU13 Swift 6 strict
   concurrency, FU14 MetricKit / XCUITest smoke).
