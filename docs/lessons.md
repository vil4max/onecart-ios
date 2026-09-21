# Lessons

Record a lesson only when a failure changed a spec, a requirement, a decision,
the core, or agent instructions. Name the check that now catches it. Earlier
review findings with regression evidence:
[engineering/review-changelog.md](engineering/review-changelog.md).

| Date | Failure | Layer changed | Check that now catches it | Replay |
|---|---|---|---|---|
| 2026-09-21 | The store-wipe gate classified Core Data failures by matching English words in a localized message, so on a non-English device Retry never recovered, while an unrelated Cocoa error from a later bootstrap step could destroy both stores | `architecture.md` F2: the wipe is armed only by a failure of `persistence.load()` itself, classified by `NSCocoaErrorDomain` code | `FragileStoreLoadTests.testWrappedLoadFailureWithNonEnglishDescriptionIsStoreLoadFailure`, `testPostLoadCocoaSaveErrorDoesNotArmHardReset` | Wrap a Cocoa store-load error in `PersistenceError.loadFailed` with a non-English description; it must classify |
| 2026-09-21 | After a partial store load, retrying in the same process failed with Cocoa 134081, so a user who hit a transient failure had to relaunch the app | `architecture.md` F11 added | `FragileStoreLoadTests.testPartialLoadFailureAllowsRetryInSameProcess` | Fail one of the two stores, retry `load()` in the same process |
| 2026-09-21 | `just verify` failed on files the repository does not own: SwiftLint walked build output inside `.claude/worktrees/**`, so a parallel agent's generated sources broke the gate | None in this repository — the check belongs to the Runtime's lint configuration and is reported to `agent-engineering-kit` | Not caught yet: keep agent derived data outside the working tree until the Runtime excludes `.claude/` | Build inside a worktree under `.claude/worktrees/` with derived data in the repository, then run `just lint` |
