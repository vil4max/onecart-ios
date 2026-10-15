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
| 2. Privacy and accounts | Product names in public logs (`application-01`); cart activity snapshots survive Delete Account and Sign out (`application-03`); unused Apple ID email and dead `signIn()` path (`data-06`, `data-07`); cached iCloud record name never reset (`data-20`); Keychain save ignores status (`data-21`); DEBUG demo writes real defaults (`application-21`); action names redacted in logs (`application-17`) | done (`f0a41e3`) |
| 3. Correctness | Shared-cart-removed notice never shown (`application-02`); widget and Live Activity use another primary-list rule (`application-04`); toggle flips stored state, not the state seen (`data-02`); category refinement drops queued widget taps (`data-03`); share creation retries non-transient errors (`data-04`); invite timeout budget (`data-13`); store references read outside the lock (`data-01`); schema alert can show twice (`application-12`); leave-recovery loop ignores cancellation (`application-13`); random `stableID` (`data-22`); English-text error classification (`data-24`); optional family scope on mutations (`data-23`); icon versus section category (`features-13`); cancelled share raises an alert (`features-14`); keyword categories (`features-12`) | done (`b8ddebc`, review repairs `52b5129`) |
| 4. Dead code | Test-only and unreachable members (`application-10`, `application-11`, `features-04`, `features-15`, `data-16`, `data-18`, `tests-16`) | done (`7f89ba9`) |
| 5. Tests and test host | Test host boots live services (`tests-01`, `tests-02`); App Group writes from tests (`tests-09`); notification permission from a view (`tests-10`, `features-19`); missing tests (`application-09`, `features-10`, `features-11`, `features-24`, `data-15`); fixtures and temp stores (`tests-11`, `tests-13`, `tests-17`, `tests-18`) | done (`e2eed5c`) |
| 6. Accessibility | Add button ignores Dynamic Type, circular widget label (`features-22`); toggle animation ignores Reduce Motion (`architecture-15`) | done (`8a9cff5`) |
| 7. Docs and hygiene | Stale architecture and ADR facts (`readiness-16`, `architecture-18`); `.gitignore` and private-data allowlist leftovers (`readiness-12`, `readiness-13`); duplicated helpers and keys (`application-14`, `data-25`); naming (`application-15`); `AppDelegate` lock and push result (`application-20`); comment policy (`application-16`, `data-27`, `features-21`, `tests-19`) | done (`7d6412e`, `5ebb494`) |

Known gap until G14: renames and category refinements keep `Product.updatedAt` (a queued widget
purchase compares it), so a retried personal-cart restore can miss a rename made on the
provisional cart. Retries happen only when selecting the restored cart failed.

## Approved by the maintainer (2026-10-15), not started

The maintainer approved every item below ("все owner-решения"). Each changes architecture, a
requirement or shipped data, so each lands as its own reviewed group with `just verify` green.

Resume point (2026-10-15, paused for a reboot): `main` is at `b31485d` with L, G1, G2 and G3
done. G4 was started and stopped before it committed; restart it from `main`. G9 was stopped
mid-way; its unfinished edits are on the local branch `worktree-agent-ae162d1647cc773bf`
(commit `4926efc`), either finish them from there or restart G9 from `main`. Every group gets
an independent review, `just verify` green and a push before the next dependent group. The
move to the iOS plugin waits for the orchestrator's "RENAME LANDED".

Planned order (status kept here):

| Group | Scope | Status |
|---|---|---|
| L | Low-severity review leftovers: rename keeps `updatedAt`, session record name reset, single-flight load preparation, share watchdog, plus the second review's lows: test stores deleted while open, tab view models outliving the tab screen, weakened invariant comments, `sync.invite_owner_only` key name | done |
| G1 | Retire dead requirement code: legacy-name helpers and REQ-CART-120, the unused join merge and REQ-CART-010 coverage, `.spec-lock.json`, the unreferenced preview video | done |
| G2 | Remove the remaining theme plumbing that does nothing in Release | done |
| G3 | Shrink the shipped-data Swift API (`ProductDraft`, unused accessors and writes) and narrow the share-environment guard; Core Data and CloudKit schema unchanged, `status = "active"` still written for v1.2.1 | done |
| G4 | Clock and sleep seam (`AppClock`) replacing direct `Date()` and `Task.sleep` | done (exceptions listed in architecture.md) |
| G5 | CloudKit sharing protocol seam; no `inMemory` branches in production | done |
| G6 | One share-mutation path; leave-purge timeout and recovery tests | pending |
| G7 | Composition root without default singletons; intents through dependencies | pending |
| G8 | Accent in the SwiftUI environment; shared app and widget mappings | pending |
| G9 | Widget shared code free of UI frameworks (no SwiftPM package: the project format has no package support) | done (`OneCartPalette` stays shared presentation) |
| G10 | Value types for the UI instead of Core Data entities (`FamilySpace` stays) | done |
| G11 | `AccountViewModel` and `CartViewModel` splits; demo hooks out of views | pending |
| G12 | Split `AppSession` (cart side, then membership and lifecycle); one wiring pattern | pending |
| G13 | Split the repository behind protocols | pending |
| G14 | Author identity in activity notifications (schema V9, additive), plus a `Product.purchaseUpdatedAt` version for queued widget purchases so renames can move `updatedAt` again and a retried personal-cart restore keeps edits from both sides. The maintainer deploys the new `CD_Product` fields to the CloudKit Production schema before the next `tf-` tag | pending |

- Architecture: split `AppSession` (`application-05`, `architecture-03`), one composition root
  without default singletons (`application-06`, `architecture-04`), view models without Core
  Data entities (`architecture-07`), one wiring pattern (`architecture-08`), a CloudKit protocol
  seam instead of `inMemory` branches and test hooks (`architecture-09`, `data-09`, `tests-05`),
  a clock seam (`data-10`, `tests-04`), a shared widget package (`architecture-14`), repository
  and view model splits (`data-08`, `features-06`, `features-07`, `features-23`, `data-26`), the
  accent in the SwiftUI environment (`features-08`), shared app and widget mappings
  (`features-17`), demo hooks out of views (`features-16`).
- Requirements: activity notifications identify authors by display name, which needs author IDs
  in the schema (`features-20`).
- Tests that need the seams above: leave-purge timeout and recovery (`tests-06`), untested
  CloudKit and classifier types (`tests-08`).
- Shared tooling (fix upstream, not in this repository): swift-format drops the trailing comma
  of a single-element multiline literal that SwiftLint `mandatory_comma` requires
  (`readiness-02`); a `$HOME`-relative default path in Tooling scripts (`readiness-07`); workflow
  comments point to `docs/ci.md` and `docs/testflight.md`, which live in `Tooling/docs/`
  (`readiness-15`).
