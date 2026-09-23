# Task — backlog round 1.7.0 (iPhone Duo, History "added by", UI smoke, concurrency)

Assignee: UI · OneCart (Claude Code session, 2026-09-23)
State: claimed
Requested by: SDLC Orchestrator relaying an owner request (2026-09-23); scope confirmed by the owner directly in this session the same day
Evidence: see Evidence history
Depends-on: none
Parallelism: up to 2

## Current status and authorization

Current outcome: plan approved; no slice landed yet.

Authorized scope (owner, direct, 2026-09-23, answers in this session and the approved plan):

1. In scope: iPhone Duo (open item 9), redesign follow-ups (open item 3), FU14 XCUITest smoke
   and MetricKit, FU13 Swift 6 strict concurrency.
2. iPhone Duo depth: "Adapt layouts" — check every screen on the iPhone Duo simulator in every
   pose and fix clipping and fold overlap with ordinary SwiftUI; no `ArrangementView`, no new UI
   concept.
3. iPhone Duo tooling: "Install runtime, verify only" — download an iOS 27.1+ simulator runtime
   through Xcode-beta; the app keeps building with Xcode 27.0 and uses no iOS 27.1 API.
4. History "added by": "Keep, I'll deploy schema" — the owner deploys
   `CD_HistoryItem.CD_createdByName` to the CloudKit Production schema before the `tf-` tag.
5. TestFlight: "Unfreeze for tf-1.7.0" — 1.7.0 build 1, `just tf-check`, `tf-1.7.0-1`, including
   the other developer's Live Activity and Siri work; no `v` tag, no App Store submission. The
   release line freezes again after the tag.
6. Plan approval covers commits per Writer step, pushing `main` with the release-prep commit as
   the head of its push, and the `tf-1.7.0-1` tag once `just tf-check` prints `Ready`.

Blocking decisions: the CloudKit Production schema deploy (owner) before the tag.
Permitted deviations: none. No new dependencies.
Material assumptions:
- A store created by 1.6.0 opens after an optional attribute is added to `HistoryItem`
  (lightweight migration); A1 proves it with a test.
- An app built with Xcode 27.0 runs on an iOS 27.1+ Duo simulator runtime; D0 proves it.
- Nothing MetricKit reports leaves the device, so `docs/privacy.md` does not change; B2
  confirms it from the code.
Next step: dispatch writers A and B.
Out of scope: open items 2, 4, 5, 6 and 7 (App Store URL check, git history rewrite, device
checks, CI runner label, SonarCloud); `ArrangementView` and hinge APIs; lifting the portrait lock
without a separate owner decision; FU06 (`PersistenceController` `@unchecked Sendable`) beyond
recording it.
Failure conditions: a REQ-covered test regresses; a 1.6.0 store fails to open; the tag is
pushed before the schema deploy; a commit by the other developer is lost or overwritten.

## Slices

| Slice | Writer | Owned files | Requirements | State |
|---|---|---|---|---|
| A1 History "added by" | writer A | `Data/Persistence/ManagedObjects.swift`, `OneCartManagedObjectModel.swift`, `FamilySpaceRepository+Products.swift`, `Features/Shopping/HistoryDetailViews.swift`, `docs/operations/release.md` §2, their tests | REQ-SYNC-020, REQ-AUTH-040 | open |
| A2 CloudKit participant seam | writer A | `Data/CloudKit/CloudKitBackendService.swift`, `CloudKitShareSupport.swift`, a new test file | REQ-SHARE-040 | open |
| A3 main-actor isolation | writer A | `Data/Authentication/AppleSignInService.swift`, `Data/Persistence/FamilySpaceRepository*.swift` | none (no behaviour change) | open |
| B1 UI smoke suite | writer B | new `OneCartUITests/`, `Application/DemoUISupport.swift`, `OneCart.xcscheme` | REQ IDs of the covered flows | open |
| B2 MetricKit | writer B | a new `Application/` file, `AppDelegate.swift`, a new test | none | open |
| B3 scene-sized chrome | writer B | `Features/Account/CartShareActivityBridge.swift`, `Application/LaunchChrome.swift`, toolbar views | none | open |
| D Duo check | integrator | fixes found on the Duo simulator | as found | open |
| R Release 1.7.0 and re-freeze | integrator | version settings, `docs/operations/releases/1.7.0.md`, status docs | none | open |

Shared files: `OneCart.xcodeproj/project.xcproj` and `Resources/Localizable.xcstrings`. Each
writer adds only its own entries; the integrator resolves conflicts.

## Evidence history

- 2026-09-23, `main` = `64eccac`: read-only exploration. FU13's language switch landed in
  `6063ea1` (every target `SWIFT_VERSION = 6.0`); `OfficialProductThumbnail` and the four unused
  strings were removed in `6e7e93c`; `HistoryItemEntity` has no `createdByName`; there is no UI
  test target; the iPhone Duo device type needs runtime 27.1+ and only 26.5 and 27.0 are
  installed; the hinge and reserved-region APIs exist only in the Xcode 27.2 beta SDK
  (`@available(iOS 27.1)`).

## Untested scope

- CloudKit "added by" across two devices, Live Activity on a device, and iPhone Duo hardware:
  simulator only.

## Writer steps

- [ ] A1 `feat(history)`: History day detail shows who added an item: `just verify`
- [ ] A2 `test(cloudkit)`: member removal and share ACLs covered through a participant seam: `just verify`
- [ ] A3 `refactor(concurrency)`: Sign in with Apple and repository view-context reads on the main actor: `just verify`, no new warnings
- [ ] B1 `test(ui)`: UI smoke suite in demo mode: `just verify`, CI `Tests`
- [ ] B2 `feat(diagnostics)`: MetricKit payloads logged on device: `just verify`
- [ ] B3 `fix(layout)`: share and launch chrome sized to the scene: `just verify`, iPhone 17 screenshots
- [ ] R1 `chore(release)`: 1.7.0 prepared: `just verify`, `just release --check`

## Current checklist

- [ ] Writers A and B landed on `main`, `just verify` green
- [ ] iPhone Duo checked in every pose; defects fixed, one commit each
- [ ] Code review rounds clean of high and medium findings; simulator smoke pass
- [ ] `main` pushed, `Tests` green
- [ ] Owner deployed `CD_createdByName` to Production
- [ ] `tf-1.7.0-1` tagged after `just tf-check` Ready
- [ ] Release line frozen again; FU13 and FU14 closed; brief moved to `docs/tasks/done/`
