# Regression notes

A note is recorded when a failure changed a spec, a requirement, a decision or the core,
and it names the check that now catches the failure.

| Date | Failure | Layer changed | Check that now catches it | Replay |
|---|---|---|---|---|
| 2026-09-21 | The store-wipe gate classified Core Data failures by matching English words in a localized message, so on a non-English device Retry never recovered, while an unrelated Cocoa error from a later bootstrap step could destroy both stores | `architecture.md` F2: the wipe is armed only by a failure of `persistence.load()` itself, classified by `NSCocoaErrorDomain` code | `FragileStoreLoadTests.test_REQ_AUTH_010_wrappedLoadFailureWithNonEnglishDescriptionIsStoreLoadFailure`, `test_REQ_AUTH_010_postLoadCocoaSaveErrorDoesNotArmHardReset` | Wrap a Cocoa store-load error in `PersistenceError.loadFailed` with a non-English description; it must classify |
| 2026-09-21 | After a partial store load, retrying in the same process failed with Cocoa 134081, so a user who hit a transient failure had to relaunch the app | `architecture.md` F11 added | `FragileStoreLoadTests.test_REQ_AUTH_080_partialLoadFailureAllowsRetryInSameProcess` | Fail one of the two stores, retry `load()` in the same process |
