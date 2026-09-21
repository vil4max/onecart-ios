# Task — audit, repository cleanup, Swift 6 and stability fixes

Assignee: onecart-audit (Claude Code session, 2026-09-20)
State: claimed
Requested by: owner (direct, 2026-09-20)
Evidence: working tree on `main`, uncommitted; `just verify` results below
Depends-on: none
Parallelism: up to 2

## Current status and authorization

Current outcome: cleanup, Swift 6 language mode, the audit fixes, widget localization, system
chrome, test isolation and dead-code removal are committed; REQ IDs, the iOS 27 deployment
target and the icon remain open.
Authorized scope: owner, direct, 2026-09-20 — audit the app, remove junk, fix the README, check the
architecture, migrate to Swift 6, raise the minimum OS to iOS 27, redesign for iOS 27, new icon,
fix the remaining audit findings. The owner delegated the four open decisions below to the agent.
Blocking decisions: none.
Permitted deviations: commit and push are not authorized; the work stays in the working tree.
Material assumptions: GitHub-hosted `macos-26` runners offer no Xcode 27; only the preview label
`xcode-27` does (checked against the runner-images README on 2026-09-20). Recheck before raising
the deployment target.
Next step: owner review of the `REQ-<AREA>-NNN` labelling in `product.md`, then decisions on the
iOS 27 deployment target and the icon.
Requirements: `docs/requirements/product.md` now defines 49 `REQ-<AREA>-NNN` IDs and a Coverage
table; 42 of them are cited by at least one test. Work completed before the IDs existed took its
intent from the audit reports and the architecture document.
Acceptance specs: see Evidence history.
Owned files: working tree of this repository.
Out of scope: history rewrite (`git-history-privacy-cleanup.md`), new product surface.
Failure conditions: a red `just verify`; weakened assertions; a wipe or sync regression.

## Decisions delegated by the owner (2026-09-20)

| Decision | Choice | Why | Rejected |
|---|---|---|---|
| Active shared cart switching on every cloud reload | Only a shared cart this device has not seen before becomes active; the known set is stored per account and removed on account deletion | Keeps the invite-accept flow (`test_REQ_SYNC_040_acceptSelectsNewestSharedWithoutDeletingOtherFamilies`) while stopping silent switches | "Adopt only when the active cart is not shared": breaks accepting a second invite |
| Minimum iOS 27 | Deferred until a generally available GitHub runner ships Xcode 27 | The `xcode-27` runner is a beta preview; a red `Tests` run blocks promotion to `testflight` (core P4, ADR 0003) | Moving CI to the preview runner now |
| Redesign | Start with the native glass add button and the progress strip as a safe-area bar (iOS 26 APIs) | Both remove custom chrome that fights the system, with low risk | Manual reorder and an extra-large widget: new product surface or a requirement change |
| Icon | Concept B ("Check"): the current outline cart with a check mark | Evolution of the shipped brand, reads as Completed | Concept A (numeral reads as "L" to some, item disappears in mono), concept C (weak at 60 px) |

Proposed requirement wording for the first row (owner approval pending, not yet in
`product.md`): "A newly joined shared cart becomes the active cart. Otherwise the cart the person
chose stays active across sync."

## Evidence history

- `4e10996` + working tree, `just verify`: `verify OK (DoD)` before any change (baseline).
- Cleanup and README slice, `just verify`: `verify OK (DoD)`.
- Swift 6 trial builds (`xcodebuild build-for-testing SWIFT_VERSION=6.0`): repeated iterations from 6
  reported errors to exit 0.
- Swift 6 enabled in the project plus three merged fix slices, `just verify`: first run failed in
  the environment (test host killed before bootstrap while four builds shared the simulator);
  rerun `verify OK (DoD)`.
- Dedupe slice merged, `just verify`: build failed (new test class not main-actor isolated under
  Swift 6); fixed; rerun `verify OK (DoD)`, 217 passing checks.

## Untested scope

- No device or two-device CloudKit run; no VoiceOver or widget gallery check.
- The synchronous `MainActor.assumeIsolated` observers in `CloudSyncCoordinator` are covered by
  the existing sync tests only.
- `ConnectivityMonitor` restart after account deletion has no test.

## Current checklist

- [x] Remove unused and duplicate assets, fix README and store README links, drop the iPad recipe
- [x] Swift 6 language mode for app, widget and tests
- [x] Duplicate product ID crash, widget snapshot on cold start, stale share watchdog
- [x] Widget accessibility labels and empty state, Reduce Motion, History grouping, row category
- [x] Name dedupe keeps purchase state and honours permissions
- [x] Active shared cart selection
- [x] Store-load failure classification for the wipe gate
- [x] Account-deletion marker written only once the destructive request starts
- [x] Widget localization
- [x] Partial store-load retry, dropped cloud reloads, `isBusy` counter, duplicate-name lookup
      without a row cap, guarded `CKShare` key access
- [x] One notification authorization path, unknown sign-in errors surfaced, demo account out of
      Release, word-boundary category inference, widget store without a silent defaults fallback
- [x] Demo mode uses its own stores and an in-memory credential
- [x] System chrome: glass add button, safe-area progress strip, accented widgets, system list
      chrome for Cart and History, system button styles, tab bar minimize
- [x] Test isolation (one session factory, suite cleanup, deterministic timing, no silent skips)
- [x] Unreferenced code removed
- [x] `REQ-<AREA>-NNN` IDs in `product.md` (proposal for owner approval) — 49 IDs across `AUTH`,
      `CART`, `HIST`, `SHARE`, `SYNC`, `SHELL`, `WIDGET` label the statements already in the
      document; 125 tests renamed to cite them; per-requirement test list in
      [product.md](../requirements/product.md#coverage). Identifiers only — no requirement wording
      and no assertion changed, so the owner still approves any change of meaning.
- [ ] Minimum iOS 27 (deferred, see decisions)
- [ ] Icon built in Icon Composer from concept B layers (owner step)

## Open items found during the work

- Seven requirements have no covering test and are listed as `none` in the Coverage table.
  Negative or view-only constraints, which the current unit target cannot assert:
  `REQ-CART-060` (no price UI), `REQ-HIST-050` (no user-facing clear-History path),
  `REQ-SHARE-100` (no invented Apple Family APIs), `REQ-SHELL-020` (История tab composition),
  `REQ-SHELL-040` (Share placed in Настройки), `REQ-SHELL-060` (display name and branding
  strings). A real gap: `REQ-SHARE-040` (Remove member kicks a participant and leaves the invite
  door unchanged) — `CKShare.removeParticipant` is never exercised, and `CKShare.Participant` has
  no public initializer, which is the same obstacle already recorded for `applyReadWriteACL`.
  Closing the view-only rows needs a decision on view-level testing, which is outside this task.
- `F10` in the fragile-test matrix (new Application files reach the compiled Sources phase) is a
  build-stage gate with no named test, so it cites no REQ ID.
- The kit checker `skills/spec-pyramid/scripts/spec_trace.py` does not recognize these IDs:
  it matches a requirement only as a Markdown heading (`^#{2,4} REQ-<AREA>-<NNN>`), so it reports
  `requirements: 0 covered: 0` and lists all 42 cited IDs as `unknown_in_specs`, even though the
  Coverage table in `product.md` is correct. The IDs here label statements inside prose,
  tables and numbered lists, which is what the source document is made of; turning each of the 49
  statements into its own heading with `Status:` and `Core:` lines would restructure an
  owner-approved L1 document rather than only add identifiers. Owner decision needed: either adopt
  the heading-per-requirement layout the kit template assumes, or treat the Coverage table as the
  project's traceability surface and leave `spec_trace.py` out of the gate. Until then the pyramid
  is traceable by review, not by that script.
- The fragile-test matrix in `docs/engineering/architecture.md` still names the pre-rename test
  functions (for example `FragileStoreLoadTests.testLoadFailureDoesNotDestroyStoreFiles`). That
  file belongs to the architecture/CI slice, not this one; its `Tests` column needs the
  `test_REQ_<AREA>_<NNN>_` names. The current names are in the Coverage table.
- `WidgetSnapshotStore.save`/`clear` call `WidgetCenter.reloadAllTimelines()` directly and
  `DevicePreferences.theme` writes to the App Group regardless of the injected suite, so tests
  cannot isolate those two paths.
- The participant upgrade loop in `applyReadWriteACL` has no unit coverage: `CKShare.Participant`
  has no public initializer.
- Catalog keys `common.unit.g`, `kg`, `l`, `ml`, `pack`, `piece` have no remaining reference.
- Widgets were never placed on a Home Screen; accented and clear rendering are unverified. The demo
  cannot reach the busy overlay, the read-only banner, connect-failed or History "show more".
- Prefix collisions in category inference remain ("eggplant" matches "egg").
- Rows that earlier demo runs wrote into a developer's real stores are not cleaned up.
