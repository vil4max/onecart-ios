# Task — 1.6.0 owner feedback before App Store submission

Assignee: OneCart · 1.6.0 closure (Claude Code session, 2026-09-22)
State: claimed
Requested by: owner (direct, 2026-09-22), after TestFlight build 116: "fix the minor issues and
ship to the App Store"; the owner checks TestFlight builds, the session prepares everything else.
Depends-on: [redesign-ios27.md](redesign-ios27.md) (done, build 116)
Parallelism: up to 2 (one writer subagent plus the integrator; at most two booted simulators)

## Authorized scope (owner, 2026-09-22)

1. Cart: the "N of M completed" progress sits at the top of the cart, not at the bottom.
2. Member names sync: each member's name comes from their Apple ID; when Apple gives none, the
   app asks for a name in a friendly way. Owner decision: full sync through a shared record,
   including the CloudKit schema change and its deployment to Production before submission.
3. Settings: the accent palette goes away; choosing an app icon also sets the accent color
   (the accent tap did not select anything on device).
4. Settings: no theme option; the app follows the device appearance.
5. Settings: no in-app language picker; one row opens the app's page in the system Settings.
6. Settings: regroup the screen by function; today the options are scattered.
7. Minor fixes: Delete Account reads as a button for VoiceOver; unused code and strings go.
8. Ship: version 1.6.0 with a new TestFlight build; the owner checks it; the session prepares
   the App Store version record and submits for review on the owner's word.

These change REQ-SHELL-010 (progress placement is not specified; no edit needed),
REQ-SHELL-030 (Settings composition) and REQ-AUTH-040 (names shared with members). The owner's
direct instructions above are the approval for those requirement edits.

Out of scope: new product surface, CI or Runtime changes, `v` tags.
Failure conditions: a red `just verify`; weakened assertions; a CloudKit schema that is not in
Production when the build reaches App Review; data loss for existing carts.

## Slices

| Slice | Owner | Files | Done when |
|---|---|---|---|
| F1 progress on top | integrator | `Features/Shopping/*`, `MainTabView.swift` | landed `0a39554` |
| F2 minor fixes | integrator | `AccountView.swift`, `ProductMedia.swift`, strings | landed `20fb95a`, `6e7e93c` |
| F3 Settings regroup, icon sets accent, no theme, system-settings row | integrator | `Features/Account/*`, `Shared/Support/AppAccentColor.swift`, `Application/AppIconOption.swift`, preferences | landed `81a07e3`; store screenshots `184d941` |
| N1 member name sync + name prompt (landed `628f946`, `9f7351f`, `87b2098`, `1daf988`, docs `HEAD`) | writer | `Data/**`, `Application/**` except `MainTabView.swift` and `AppIconOption.swift`, `Features/Onboarding/*`, new tests | shared profile record per member; members list shows names; prompt when Apple gives no name; REQ-AUTH-040 edited with tests; `just verify` |
| S1 ship | integrator | version, release notes, ASC | build number bump, `tf-1.6.0-2`, CloudKit schema in Production, version record ready, submission on the owner's word |

## Evidence

- 2026-09-22: F1, F2 landed; `just verify` OK on `0a39554`.
- 2026-09-22: F3 landed (`81a07e3`): Settings in three groups, icon sets the accent (simulator:
  tapping Ocean switched icon and accent), no theme/accent/language picker; the system-Settings
  row opened the Settings root on the Debug simulator build (Apple documents the app page when
  one exists; to check on a TestFlight install). Store screenshots for cart and Settings retaken
  in English and Russian (`184d941`); uploading them to App Store Connect needs the owner or
  Claude in Chrome (the in-app browser cannot upload files, ASC's CSP blocks a local fetch).
- 2026-09-22: N1 by writer (worktree, 4 commits) cherry-picked cleanly; the integrator reviewed
  the naming order (profile → iCloud name → "Member N"), owner/member record-name matching and
  the serial publish; `architecture.md` moved to V8 and `common.default_member` removed.
  `just verify` OK (230 XCTest + Swift Testing), `spec_trace.py` 49/49. Writer worktree, branch
  and simulator removed.
- 2026-09-22: App Store Connect version record 1.6.0 created (Prepare for Submission).
- Pending on the owner's word: CloudKit schema (`CD_MemberProfile` into Development, then
  deploy to Production), push `main`, `tf-1.6.0-2`, What to Test, screenshot upload, What's
  New, submission for review.
