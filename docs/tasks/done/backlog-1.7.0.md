# Task — backlog round 1.7.0 (iPhone Duo, History "added by", UI smoke, concurrency)

Assignee: UI · OneCart (Claude Code session, 2026-09-23)
State: done
Requested by: SDLC Orchestrator relaying an owner request (2026-09-23); scope confirmed by the owner directly in this session the same day
Evidence: `tf-1.7.0-1` on `403d909`; see Evidence history
Depends-on: none
Parallelism: up to 2

## Current status and authorization

Current outcome: done — every Writer step on `main`, pushed as `403d909`, `tf-1.7.0-1` tagged; release line frozen again. Duo check blocked on a runtime (open item 9).

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

7. Added 2026-09-23 (owner, direct, this session; plan approved): review of the other developer's
   Live Activity and Siri work (`989f4c4`, `92c763f`, `7203f09`) against its proposed
   REQ-WIDGET-040…060 and REQ-SIRI-010…040, and fixes for every gap in four groups — trip
   lifecycle, Siri startup and errors, wording and consistency, accessibility. Decisions: "Split
   on и/і/and too"; "Allow on locked phone"; "Mark after 1 hour" (Live Activity stale date);
   "Hold tag until fixes". Relayed from the SDLC Orchestrator session, not given here: the Live
   Activity and Siri work is final for 1.7.0; its requirements stay proposed.

Blocking decisions: none (the CloudKit Production schema deploy is done).
Permitted deviations: none. No new dependencies.
Material assumptions:
- A store created by 1.6.0 opens after an optional attribute is added to `HistoryItem`
  (lightweight migration); A1 proves it with a test.
- An app built with Xcode 27.0 runs on an iOS 27.1+ Duo simulator runtime: not provable this
  round, no installed runtime supports the device (see Evidence history).
- Nothing MetricKit reports leaves the device, so `docs/privacy.md` does not change; B2
  confirms it from the code.
Next step: none; the owner's device checks follow the What to Test of `tf-1.7.0-1`.
Out of scope: open items 2, 4, 5, 6 and 7 (App Store URL check, git history rewrite, device
checks, CI runner label, SonarCloud); `ArrangementView` and hinge APIs; lifting the portrait lock
without a separate owner decision; FU06 (`PersistenceController` `@unchecked Sendable`) beyond
recording it.
Failure conditions: a REQ-covered test regresses; a 1.6.0 store fails to open; the tag is
pushed before the schema deploy; a commit by the other developer is lost or overwritten.

## Slices

| Slice | Writer | Owned files | Requirements | State |
|---|---|---|---|---|
| A1 History "added by" | writer A | `Data/Persistence/ManagedObjects.swift`, `OneCartManagedObjectModel.swift`, `FamilySpaceRepository+Products.swift`, `Features/Shopping/HistoryDetailViews.swift`, `docs/operations/release.md` §2, their tests | REQ-SYNC-020, REQ-AUTH-040 | done `677e7b6` |
| A2 CloudKit participant seam | writer A | `Data/CloudKit/CloudKitBackendService.swift`, `CloudKitShareSupport.swift`, a new test file | REQ-SHARE-040, REQ-SHARE-020 | done `5b3ab04` |
| A3 main-actor isolation | writer A | `Data/Authentication/AppleSignInService.swift`, `Data/Persistence/FamilySpaceRepository*.swift` | none (no behaviour change) | done `f53582b` |
| B1 UI smoke suite | writer B | new `OneCartUITests/`, `Application/DemoUISupport.swift`, `OneCart.xcscheme` | REQ-CART-030, REQ-CART-040, REQ-SHELL-020, REQ-SHELL-030 | done `4f0be81` |
| B2 MetricKit | writer B | a new `Application/` file, `AppDelegate.swift`, a new test | none | done `aa03564`, C1 `1479d7b` |
| B3 scene-sized chrome | writer B | `Features/Account/CartShareActivityBridge.swift`, `Application/LaunchChrome.swift`, `Features/Account/AccountView.swift` | none | done `9318c38` (toolbars unchanged, see Evidence history) |
| D Duo check | integrator | fixes found on the Duo simulator | as found | blocked (no runtime supports the device) |
| L1–L7 trip lifecycle, stale date, refusal texts, trip a11y | writer L | `ShoppingTripActivityController.swift`, `AppSession+ShoppingTrip.swift`, `AppSession+Widget.swift`, `AppSession+FamilySelection.swift`, `SessionBootstrapper.swift`, `ShoppingTripLiveActivity.swift`, `EndShoppingTripIntent.swift`, `CartProgressHeader.swift`, their tests | REQ-WIDGET-040…060, REQ-SIRI-030 | done `019d219`…`d1b7eda` |
| S1–S6 Siri startup, errors, separators, order, speech | writer S | `AppSession+Intents.swift`, `Intents/CartAppIntents.swift`, `Intents/OneCartShortcuts.swift`, `AppSession+Welcome.swift` (`start()`), `HouseholdCartCoordinator.swift`, `AppShortcuts.xcstrings`, `CartIntentTests.swift`, `CartTestSupport.swift`, SIRI wording in `product.md` | REQ-SIRI-010…040 | done `04c26fb`…`d13c80b` |
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
- 2026-09-23: the iOS 27.2 (24B5084k) simulator runtime was installed via Xcode-beta
  (`xcodebuild -downloadPlatform iOS`). No installed runtime (26.5, 27.0, 27.2) lists the
  `iPhone Duo` device type as supported; `xcrun simctl create … iPhone-Duo … iOS-27-2` fails with
  `SimError 403 Incompatible device`. Duo check D0: BLOCKED until a runtime that supports the
  device ships. The owner said via the orchestrator the same day that the Duo check does not block
  `tf-1.7.0-1`; B3's scene-sizing fixes stand as the Duo preparation of this round.
- 2026-09-23: writer A landed A1 `677e7b6`, A2 `5b3ab04`, A3 `f53582b` (cherry-picked from its
  worktree; `just verify` OK before each commit, 242 XCTest tests, 0 failures; build warnings
  26 → 17). A1 proved automatic lightweight migration for the new optional attribute.
  Found, not fixed (behaviour change out of scope): member removal matches a participant by
  record name or email only, while the members list also identifies by phone number, so a
  phone-only member would show but fail removal with "participant not found".

- 2026-09-23: writer B landed B1 `4f0be81`, B2 `aa03564`, B3 `9318c38` (cherry-picked; one
  `project.xcproj` conflict in the test file list resolved by keeping both entries). `just verify`
  on `main` at `9318c38`: `verify OK (DoD)`, 242 XCTest unit tests and the Swift Testing suites
  0 failures, 3 UI smoke tests 0 failures in 47.7 s. The UI-test-launched app does not see
  `XCTestConfigurationFilePath`, so startup and demo seeding run as in a normal launch.
  B3 deviation: toolbar items were not converted to `Label`; on iOS 27.0 every variant tried
  (default, `.titleAndIcon`, a custom style) dropped the member count or restyled Save as a filled
  button on a normal iPhone, so they stay as they are until a Duo runtime shows whether vertical
  bars need them. Screenshots:
  `agent-artifacts/2026-09-23/onecart-backlog-1.7.0/work/b3-screenshots/`.
  B2 finding: the iOS 27.0 SDK marks `MXMetricManager` and `MXMetricManagerSubscriber`
  `API_TO_BE_DEPRECATED` ("Use MetricManager instead."); `MetricManager` (async
  `metricReports` / `diagnosticReports`) is available from iOS 27.0, the deployment target, so C1
  moves to it before release.

- 2026-09-23: writer C landed C1 `1479d7b` (`just verify` in its worktree: `verify OK (DoD)`,
  242 XCTest + Swift Testing 423 passed, UI 3 passed; no MetricKit warnings; no `MX*` symbols
  left). `launches=`/`hangs=` now sum histogram counts; the B2 code logged
  `MXHistogram.totalBucketCount`, the number of buckets. On `main` at `1479d7b` every test passed
  (242 XCTest, 3 UI in 64.2 s) but `verify` ended "Inputs changed during verify" because the
  release notes were edited during the run; the R1 run re-proves it.
- 2026-09-23, review round 1 (`/code-review high`, `64eccac..d7c2403`): no high finding. Medium:
  the new field breaks CloudKit export for signed builds until deployed (Debug and Release pin
  Production) — resolved by deploying before any push; the to-be-deprecated `MXMetricManager` —
  fixed by C1. Low, recorded: phone-only members cannot be removed (pre-existing); the share
  popover lives on a lazy Form row; no automated check for the scene-sized share and launch
  chrome; `displayableName` duplicates `String.nilIfBlank`. Round 2 on C1 alone: no finding.
- 2026-09-23: owner approved in session ("Add and deploy"); the integrator added
  `CD_createdByName` (String) to `CD_HistoryItem` in the Development schema, reviewed the deploy
  dialog (one new field, no index or security-role change) and deployed. Console: "The schema is
  deployed to Production"; Production `CD_HistoryItem` lists `CD_createdByName STRING`.

- 2026-09-23: writer L landed L1 `019d219`, L2 `1bc8307`, L3 `a38f62c`, L4 `580c737`, L5
  `c95f585`, L6 `1125328`, L7 `d1b7eda` (cherry-picked, no conflict). Each step began with a
  REQ-WIDGET test that failed on the unfixed code (L2 and L4 made reliable with a fake backend that
  holds `end` until released); `just verify` printed `verify OK (DoD)` after every step.
  `ShoppingTripError.unavailable` became `.noCart`, `.activitiesOff`, `.systemRefused` with their
  own texts. After a relaunch the header offers start until the first cart update adopts the
  running trip. Owner decision the same day: "Keep 3 rows, 30 pt tall" — the card's check control
  is 44 pt wide and 30 pt tall, because three 44 pt rows would pass the 160 pt Live Activity
  height Apple says may be truncated; the stop control is 44 × 44. Known limits: a finished card
  that outlives an app relaunch still waits out its five minutes (the finishing id is in memory);
  the revoked-credential branch runs only on a device; cart rows wrap badly at accessibility
  sizes (outside this slice). Screenshots:
  `agent-artifacts/2026-09-23/onecart-backlog-1.7.0/work/l7-screenshots/`.

- 2026-09-23: writer S landed S1 `04c26fb`, S2 `dbebbf7`, S3 `def2670`, S4 `98828c2`, S5
  `f7e9aac`, S6 `d13c80b` (cherry-picked; the REQ coverage table conflicted four times and was
  merged by keeping writer L's REQ-WIDGET rows and writer S's REQ-SIRI rows). Each step began with a
  REQ-SIRI test failing on the unfixed code; `just verify` OK before each commit. S6: Apple's
  `LocalizedStringResource` and `IntentSystemContext.locale` documentation confirms late
  resolution in the request's language, so dialogs and `CartIntentError` now carry
  `LocalizedStringResource`. Outside the owned list: one line in `AppSession+CartMutations.swift`
  (a task-local `CartIntentContext` suppresses the in-app alert) and two new test files. A
  background start arms the store wipe as a foreground start does; the wipe still runs only on the
  user's Welcome Retry, so `SessionBootstrapper` needed no change.
- 2026-09-23, `main` at `d13c80b`: `just verify` OK (DoD), 258 XCTest + Swift Testing + 3 UI,
  0 failures; `spec_trace.py` 56/56.
- 2026-09-23, review round 1 on L and S (`/code-review high`): medium — `clearAccountData` now ended
  the trip unconditionally, so a failed startup (e.g. Siri while iCloud is briefly unavailable) or a
  reload before the account is restored ended a signed-in user's trip; fixed spec-first in
  `9ecf5ee` (`test_REQ_WIDGET_060_failedStartup_keepsTheRunningTrip` failed before: 0 running, one
  end). Low — the startup-deadline timer relied on same-turn ordering; made explicit in `aba4319`.
  Low, owner trade-off — splitting on the word for "and" splits names that contain it. Round 2 on
  the two fixes: no finding. `just verify` after each: OK (DoD), 259 XCTest + Swift Testing + 3 UI.
- 2026-09-23, simulator smoke on iPhone 17 (iOS 27.0), demo owner at `aba4319`: the trip starts
  from the header (header shows End trip), a check updates the count (2 → 3 of 5), End trip
  returns the header to start, and the History day detail shows "Added by" and "Bought by" on each
  item. Not exercised: the Lock Screen card and Dynamic Island, Siri by voice.

- 2026-09-23: `just verify` OK (DoD) and `just release --check` "Release preflight OK" on
  `403d909`; pushed `64eccac..403d909` (30 commits, private-data scan clean); `Tests` run
  35852905594 success; `just tf-check` Ready; `tf-1.7.0-1` pushed with the What to Test
  annotation; the `TestFlight` workflow succeeded and `origin/testflight` is `403d909`.

## Resume prompt

OneCart 1.7.0 round is done: `tf-1.7.0-1` on `403d909`, release line frozen again. Nothing is in
flight. On resume, read `docs/planning/project-state.md` (open items 2, 4–12) and wait for the
owner to pick the next task; do not unfreeze the release line or tag without the owner's word.

## Untested scope

- CloudKit "added by" across two devices, Live Activity on a device, and iPhone Duo hardware:
  simulator only.

## Writer steps

- [x] A1 `feat(history)`: History day detail shows who added an item: `just verify` — 677e7b6
- [x] A2 `test(cloudkit)`: member removal and share ACLs covered through a participant seam: `just verify` — 5b3ab04
- [x] A3 `refactor(concurrency)`: Sign in with Apple and repository view-context reads on the main actor: `just verify`, no new warnings — f53582b
- [x] B1 `test(ui)`: UI smoke suite in demo mode: `just verify`, CI `Tests` — 4f0be81
- [x] B2 `feat(diagnostics)`: MetricKit payloads logged on device: `just verify` — aa03564
- [x] C1 `refactor(diagnostics)`: MetricKit reports read through the iOS 27 `MetricManager` instead of the to-be-deprecated `MXMetricManager`: `just verify` — 1479d7b
- [x] B3 `fix(layout)`: share and launch chrome sized to the scene: `just verify`, iPhone 17 screenshots — 9318c38
- [x] R1 `chore(release)`: 1.7.0 prepared: `just verify`, `just release --check` — 1180a7d
- [x] L1 `fix(trip)`: Stop dismisses a finished trip at once: failing REQ-WIDGET-060 test first, `just verify` — 019d219
- [x] L2 `fix(trip)`: a trip still starting ends when the account goes away: REQ-WIDGET-060 tests, `just verify` — 1bc8307
- [x] L3 `fix(trip)`: a trip of no signed-in account is dropped at launch: REQ-WIDGET-050/060 tests, `just verify` — a38f62c
- [x] L4 `fix(trip)`: a Lock Screen check updates the card before returning: REQ-WIDGET-050 test, `just verify` — 580c737
- [x] L5 `fix(trip)`: a swiped-away trip is noticed before starting or reporting: REQ-WIDGET-060 test, `just verify` — c95f585
- [x] L6 `fix(trip)`: one-hour stale date and cause-specific refusal texts: REQ-WIDGET-040/050 tests, `just verify` — 1125328
- [x] L7 `fix(a11y)`: trip progress labelled, trip controls ≥ 44 pt, header stacks at large sizes: tests, `just verify` — d1b7eda
- [x] S1 `fix(siri)`: a failed background start is reported and retried: REQ-SIRI-040 tests, `just verify` — 04c26fb
- [x] S2 `fix(siri)`: the startup wait has a 10 s limit: REQ-SIRI-040 test, `just verify` — dbebbf7
- [x] S3 `fix(siri)`: Siri waits for the household cart instead of blaming iCloud: REQ-SIRI-010 test, `just verify` — def2670
- [x] S4 `fix(siri)`: a partial multi-item add is reported; no in-app alert from Siri: REQ-SIRI-010 test, `just verify` — 98828c2
- [x] S5 `fix(siri)`: split on и/і/and; read back in screen order: REQ-SIRI-010/020 tests, `just verify` — f7e9aac
- [x] S6 `fix(siri)`: speech in Siri's language with plural counts: REQ-SIRI-040 tests, `just verify` — d13c80b

## Current checklist

- [x] Writers A and B landed on `main`, `just verify` green (`9318c38`)
- [ ] iPhone Duo checked in every pose — blocked: no simulator runtime supports the device (open item 9)
- [x] Code review rounds clean of high and medium findings; simulator smoke pass
- [x] `main` pushed (`64eccac..403d909`), `Tests` green on `403d909`
- [x] `CD_createdByName` deployed to Production (2026-09-23)
- [x] `tf-1.7.0-1` tagged after `just tf-check` Ready
- [x] Release line frozen again; FU13 and FU14 closed; brief moved to `docs/tasks/done/`
