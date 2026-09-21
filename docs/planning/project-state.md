# Project state — 2026-09-17

Snapshot for resuming work after a pause. Update it when the release or CI state changes.

## Product

| Item | State |
|---|---|
| App Store | 1.2 (91) live |
| In App Review | **1.2.1 (105)**, submitted 2026-09-17 10:13, auto-release after approval — [releases/1.2.1.md](../operations/releases/1.2.1.md) |
| Scope | Stability first: SIWA → one living cart → name-only add → Completed → History by day → invite from Settings ([product.md](../requirements/product.md)) |
| Version in repo | `MARKETING_VERSION` 1.3.0, build 1 (Xcode Cloud assigns uploaded build numbers) |
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
- `release`: frozen at `a5e6915` (tag `v1.2.1`); nothing moves it since ADR 0004. Its Xcode Cloud
  workflow "App Store candidate (release tag)" is unused, to be retired in App Store Connect.
- Current refs: `testflight` at `bbd884c` (1.3.0, promoted by the last every-push run before the
  switch); tags `v1.2.0`, `v1.2.1`; no `tf-` tags yet.

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
4. CI runs the Runtime's shared `Tests` workflow on the public-preview `xcode-27` image (Xcode
   27.0, iPhone 17 on iOS 27.0), the only GitHub-hosted label carrying the iOS 27 SDK the app now
   requires. Once a GA label ships Xcode 27, set the `IOS_RUNNER` and `IOS_DEVELOPER_DIR`
   repository variables to it, and treat preview withdrawal as a TestFlight outage — no `tf-`
   tag can pass without a green `Tests` run ([ADR 0003](../decisions/0003-ci-split.md), "Runner
   image risk"). The `#if compiler(>=6.4)` guard in `CartWidgetViews.swift` is removed.
5. SonarCloud Automatic Analysis is attached to PRs but not part of CI (Sonar in CI was declined);
   decide whether to keep the app.
6. Follow-ups from [review-changelog.md](../engineering/review-changelog.md) (FU13 Swift 6 strict
   concurrency, FU14 MetricKit / XCUITest smoke).
