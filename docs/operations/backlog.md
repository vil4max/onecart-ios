# Backlog

Open engineering work and the decisions it waits on. Every requirement in
[product.md](../requirements/product.md) is approved and has covering tests; the deferred product
ideas there (multi-cart UI, history assistant, History retention) stay unplanned until the
maintainer takes them on.

## In progress: audit fixes (started 2026-10-15)

The source is an engineering audit of 2026-10-10, re-verified against `f07a160`. Each group ends
with `just verify` green and one commit. Finding IDs (`oc-<scope>-NN`) refer to that audit.

| Group | Scope | Status |
|---|---|---|
| 1. Lint | Zero SwiftLint warnings under the shared config | done (`e112074`) |
| 2. Privacy and accounts | Product names in public logs (`application-01`); cart activity snapshots survive Delete Account and Sign out (`application-03`); unused Apple ID email and dead `signIn()` path (`data-06`, `data-07`); cached iCloud record name never reset (`data-20`); Keychain save ignores status (`data-21`); DEBUG demo writes real defaults (`application-21`); action names redacted in logs (`application-17`) | pending |
| 3. Correctness | Shared-cart-removed notice never shown (`application-02`); widget and Live Activity use another primary-list rule (`application-04`); toggle flips stored state, not the state seen (`data-02`); category refinement drops queued widget taps (`data-03`); share creation retries non-transient errors (`data-04`); invite timeout budget (`data-13`); store references read outside the lock (`data-01`); schema alert can show twice (`application-12`); leave-recovery loop ignores cancellation (`application-13`); random `stableID` (`data-22`); English-text error classification (`data-24`); optional family scope on mutations (`data-23`); icon versus section category (`features-13`); cancelled share raises an alert (`features-14`); keyword categories (`features-12`) | pending |
| 4. Dead code | Test-only and unreachable members (`application-10`, `application-11`, `features-04`, `features-15`, `data-16`, `data-18`, `tests-16`) | pending |
| 5. Tests and test host | Test host boots live services (`tests-01`, `tests-02`); App Group writes from tests (`tests-09`); notification permission from a view (`tests-10`, `features-19`); missing tests (`application-09`, `features-10`, `features-11`, `features-24`, `data-15`); fixtures and temp stores (`tests-11`, `tests-13`, `tests-17`, `tests-18`) | pending |
| 6. Accessibility | Add button ignores Dynamic Type, circular widget label (`features-22`); toggle animation ignores Reduce Motion (`architecture-15`) | pending |
| 7. Docs and hygiene | Stale architecture and ADR facts (`readiness-16`, `architecture-18`); `.gitignore` and private-data allowlist leftovers (`readiness-12`, `readiness-13`); duplicated helpers and keys (`application-14`, `data-25`); naming (`application-15`); `AppDelegate` lock and push result (`application-20`); comment policy (`application-16`, `data-27`, `features-21`, `tests-19`) | pending |

## Waiting on the maintainer

Confirmed by the audit, not started: each changes architecture, a requirement or shipped data.

- Architecture: split `AppSession` (`application-05`, `architecture-03`), one composition root
  without default singletons (`application-06`, `architecture-04`), view models without Core
  Data entities (`architecture-07`), one wiring pattern (`architecture-08`), a CloudKit protocol
  seam instead of `inMemory` branches and test hooks (`architecture-09`, `data-09`, `tests-05`),
  a clock seam (`data-10`, `tests-04`), a shared widget package (`architecture-14`), repository
  and view model splits (`data-08`, `features-06`, `features-07`, `features-23`, `data-26`), the
  accent in the SwiftUI environment (`features-08`), shared app and widget mappings
  (`features-17`), demo hooks out of views (`features-16`).
- Requirements: REQ-CART-120 traces to legacy-name helpers that nothing calls
  (`features-03`); REQ-CART-010 traces to a join merge that nothing calls (`data-05`); activity
  notifications identify authors by display name, which needs author IDs in the schema
  (`features-20`); the theme preference does nothing in Release (`application-08`).
- Shipped data: leftover catalog and price fields still synced to CloudKit (`data-17`); the
  share-environment guard and legacy wipe (`data-19`).
- Tests that need the seams above: leave-purge timeout and recovery (`tests-06`), untested
  CloudKit and classifier types (`tests-08`).
- Repository: `docs/requirements/.spec-lock.json` has no reader (`readiness-11`); the
  unreferenced 3.5 MB `assets/store/preview/tf-welcome-siwa.mp4` (`readiness-17`).
- Shared tooling (fix upstream, not in this repository): swift-format drops the trailing comma
  of a single-element multiline literal that SwiftLint `mandatory_comma` requires
  (`readiness-02`); a `$HOME`-relative default path in Tooling scripts (`readiness-07`); workflow
  comments point to `docs/ci.md` and `docs/testflight.md`, which live in `Tooling/docs/`
  (`readiness-15`).
