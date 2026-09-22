# Task — iOS 27 redesign, MVVM refactoring and test coverage

Assignee: OneCart · redesign iOS 27 (Claude Code session, 2026-09-22)
State: claimed
Requested by: owner (direct, 2026-09-22): "deep redesign for modern iOS 27 + code refactoring
+ test coverage"
Evidence: see Evidence history
Depends-on: none (1.5.0 is in App Review; 1.5.1 (115) is in TestFlight)
Parallelism: up to 2

## Current status and authorization

Current outcome: Phase 1 landed on `main` (S1 c07dbe5, S2 7be3b4a + cdf6bec, S3 6ddc3d2); Phase 2 R1 and Phase 3 T2 in progress.
Authorized scope (owner, 2026-09-22, three decisions):

1. Redesign every screen for iOS 26/27 idioms; the information architecture stays: three tabs
   (Cart, History, Settings) and the core path of [core.md](../core.md) /
   [product.md](../requirements/product.md). No requirement edits are proposed by this task.
2. Full architecture refactoring: `@Observable` instead of `ObservableObject`, a real ViewModel
   per screen with initializer-injected protocols, and screens that no longer reach
   `AppSession` directly. `AppSession` stays the composition root and app state; its public
   surface is split into service protocols.
3. Tests: ViewModel and service tests only, no XCUITest and no snapshot library. Targets:
   app-target line coverage ≥ 70 % (46.28 % at the start) and 49/49 requirements traced by
   `spec_trace.py` (42/49 at the start).

Permitted deviations: commit per slice is authorized (owner, 2026-09-22, "готовь" flow of the
previous tasks); push and tf- tags only on the owner's word in the session. No new
dependencies. Version for the round: 1.6.0 (MINOR).
Blocking decisions: none.
Material assumptions: iOS 27 SDK (Xcode 27.0) is the build toolchain locally and on the
`xcode-27` runner; the kit's `swiftui-expert-skill` references describe the iOS 26/27 APIs to
use (`liquid-glass.md`, `toolbar-patterns.md`, `sheet-navigation-patterns.md`,
`state-management.md`). Verify an API's availability with `apple-knowledge` before relying on it.
Owned files: see the slice table; two writers never share a file.
Out of scope: new product surface (prices, multi-cart, catalog), widget feature changes beyond
visual alignment, CI or Runtime changes, App Store submission of 1.6.0.
Failure conditions: a red `just verify`; weakened or deleted assertions; a behaviour change
without a requirement; a screen that regresses accessibility (Dynamic Type, VoiceOver labels)
or dark mode.

## Baseline (2026-09-22, `main` 86bb72d)

- 14 291 app lines, 7 084 test lines, 227 tests, `just verify` green.
- Coverage (last local run): app 46.28 %; every SwiftUI screen file 0 %
  (`AccountView` 1 812 executable lines, `ShoppingListView` 1 200, `AccountRows` 728,
  `CartConfettiView` 327, `CartChromeViews` 321, `CartProductRow` 293, `HomeView` 276);
  `FamilyInviteLinkBuilder` 1 %, `CloudKitBackendService` 10 %, `HistoryViews` 17 %,
  `AppSession+Membership` 33 %.
- `AppSession`: `ObservableObject`, 19 `@Published`, 1 711 lines across 9 files; orchestration
  is already delegated (`CartSyncService`, `CartContentStore`, `SessionBootstrapper`,
  `CloudSyncCoordinator`, `InviteLinkPreparer`, `HouseholdCartCoordinator`). Observation is
  bridged with four `objectWillChange` sinks and one manual `objectWillChange.send()`
  (`AppSession+Hosts.swift:94`). Eight screens read it through `@EnvironmentObject`.
- ViewModels are shells: `ShoppingViewModel` forwards two calls; `AccountViewModel` and
  `WelcomeViewModel` take `AppSession` directly.
- Uncovered requirements: REQ-CART-060, REQ-HIST-050, REQ-SHARE-040, REQ-SHARE-100,
  REQ-SHELL-020, REQ-SHELL-040, REQ-SHELL-060.

## Plan

### Phase 1 — foundation (behaviour unchanged; the 227 tests are the safety net)

| Slice | Writer | Owned files | Done when |
|---|---|---|---|
| S1 `@Observable` state | A | `OneCart/Application/AppSession*.swift`, `CartSyncService.swift`, `CartContentStore.swift`, `InviteLinkPreparer.swift`, `SessionTypes.swift`, `RootView.swift`, `MainTabView.swift`, `OneCartApp.swift`, `LaunchChrome.swift`, `DemoUISupport.swift`, `Shared/Support/DevicePreferences*.swift`; the single `@EnvironmentObject` line in each screen file becomes `@Environment(AppSession.self)`; `Tests/CartTestSupport.swift` and any test that observes `objectWillChange` | No `ObservableObject`, `@Published`, `@StateObject`, `@EnvironmentObject` or `objectWillChange` left in the app target; environment injection through `.environment(_:)`; `just verify` green |
| S2 service protocols + ViewModels | B | new `OneCart/Application/Services/` (protocol files), new `OneCart/Application/AppSession+Services.swift` (conformances only), `Features/*/…ViewModel.swift` (new `CartViewModel`, `HistoryViewModel`; rewritten `AccountViewModel`, `WelcomeViewModel`), new `Tests/Support/Fake*.swift`, new `Tests/*ViewModelTests.swift` | Every ViewModel is `@MainActor @Observable`, depends only on protocols, and has tests with fakes; the protocol set covers what the screens call today (cart editing, history browsing, membership, account, welcome sign-in, session state); `just verify` green. Views are not touched in S2 |
| S3 wire screens to ViewModels | B (after S1 and S2 land) | `OneCart/Features/**` views | No `AppSession` symbol inside `OneCart/Features/`; ViewModels are created at the screen boundary (`RootView`/`MainTabView`, A's files, by a factory B specifies); `just verify` green; simulator smoke of the core path |

Protocol naming follows `swift-protocol-naming.mdc` (nouns for roles, `-ing` for capabilities,
no `Protocol` suffix). Fakes conform to the same protocols as production.

### Phase 2 — redesign, screen by screen (iOS 26/27 idioms; requirements unchanged)

| Slice | Writer | Screen | Direction |
|---|---|---|---|
| R1 | A | Cart (`ShoppingListView`, `CartChromeViews`, `CartProductRow`, `CartAddFAB`, `HomeView`) | Glass tab bar with `tabViewBottomAccessory` for the progress strip; quick add through the tab-bar search field; add button morphs into the composer (`glassEffectID`, `GlassEffectContainer`); swipe actions; `presentationDetents` sheets; native `List` sections with the Completed group; celebration kept |
| R2 | B | Settings (`AccountView`, `AccountRows`, `ProfileView`) and Welcome (`WelcomeView`) | Native `Form` with inset-grouped sections; inline icon and accent pickers; member list with system rows and swipe to remove; share as a secondary action (REQ-SHELL-040); Welcome with the brand hero, feature rows and Sign in with Apple, no custom chrome |
| R3 | A | History (`HistoryViews`, `HistoryDetailViews`) | Days as a timeline list, detail through `NavigationStack`, read-only (REQ-SHELL-020), caption for the overnight rule, "show more" paging |
| R4 | B | Widgets (`OneCartWidgets/*`) | Visual alignment with the new palette and glass; no behaviour change |

Every slice: dark mode, Dynamic Type (up to accessibility sizes), VoiceOver labels on controls,
screenshots into `work/` of the agent artifacts for the owner's review, simulator smoke of the
screen.

### Phase 3 — coverage

| Slice | Writer | Target |
|---|---|---|
| T1 | A | The seven uncovered requirements: tests or, where the requirement is a negative UI constraint (CART-060, HIST-050, SHARE-100), a ViewModel-level assertion that the corresponding action does not exist in the ViewModel's API surface; update the Coverage table in `product.md` |
| T2 | B | `FamilyInviteLinkBuilder` (pure builder), `AppSession+Membership` through the membership protocol with fakes, `CloudKitBackendService` error paths through the existing `CloudKitErrors` mapping |
| T3 | integrator | Coverage report from the `just verify` xcresult (`xccov --report --json`); gate: app ≥ 70 %, `spec_trace.py` 49/49 |

### Closure

Version bump to 1.6.0, release notes (`docs/operations/releases/1.6.0.md`), `project-state.md`,
`docs/engineering/architecture.md` updated for the ViewModel layer, new store screenshots from
the demo UI, push and `tf-1.6.0-1` on the owner's word, flow report to the kit session.

## Working rules for writers

- One worktree per writer; only the owned files of the current slice; ask the integrator before
  touching anything else.
- Loop: edit → `just build`/`just lint` → targeted tests → `just verify` at the end of the slice.
  Two writers share one simulator; a failed run with "test host" or "unable to boot" wording is
  contention: wait and retry once, do not create devices.
- Commit per slice with the repository's commit policy (English, `<type>(<scope>): <summary>`,
  body with why, changes, validation actually run). No push.
- Comments: English, only where the code cannot carry the intent. No `*Protocol` suffix. No
  force unwraps without justification. Value types preferred.
- Report back: material changes, verification results with commands, unresolved items, the
  commit hashes.

## Evidence history

- 2026-09-22, `main` 86bb72d: baseline `just verify` green (227 tests); coverage figures above
  from the xcresult of that run.
- 2026-09-22, S1 `c07dbe5` (from writer A `4081ece`): `AppSession`, `CartSyncService`,
  `CartContentStore`, `InviteLinkPreparer`, `DevicePreferences` are `@MainActor @Observable`;
  Combine bridges and `objectWillChange` gone; `just verify` OK, 227 tests.
- 2026-09-22, S2 `7be3b4a`, `cdf6bec` (from writer B): nine role protocols in
  `Application/Services/`, declarative conformances in `AppSession+Services.swift`, four
  `@Observable` ViewModels, fakes and 36 Swift Testing cases; `just verify` OK.
- 2026-09-22, S3 `6ddc3d2`: screens wired to ViewModels at the screen boundary
  (`RootSessionView`, `MainTabView`); no `AppSession` symbol in `Features/`; no
  `ObservableObject`/`@StateObject`/Combine in the app target; `just verify` OK; simulator
  smoke of welcome, cart, history, settings matched the previous rendering.
- Coverage after Phase 1: app 47.77 % (8143/17047); screens still 0 % by design (ViewModels
  carry the logic now).
- Edge case (harness): agent worktrees are created from `origin/main`, not local `HEAD`; every
  writer prompt now starts with `git reset --hard main`.
