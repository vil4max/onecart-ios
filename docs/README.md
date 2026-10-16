# Docs

Documentation is layered: each layer details the one above it, and a change starts at the
highest affected layer.

| Layer | Question | Source |
|---|---|---|
| Core | Goal, language, priorities, constraints | [core.md](core.md) |
| Requirements | Thesis, living cart, Completed → History, membership, widgets | [requirements/product.md](requirements/product.md) |
| Decisions | Why CloudKit; which CI owns tests vs TestFlight | [decisions/0002-cloudkit-native-backend.md](decisions/0002-cloudkit-native-backend.md), [decisions/0003-ci-split.md](decisions/0003-ci-split.md), [decisions/0004-tag-gated-testflight.md](decisions/0004-tag-gated-testflight.md) |
| Tests | Which tests prove the requirements? | `OneCart/Tests/` — XCTest `func test_REQ_<AREA>_<NNN>_…()`, Swift Testing `@Test("REQ-<AREA>-<NNN>: …")`; IDs and the per-requirement test list live in [requirements/product.md](requirements/product.md#coverage) |
| Engineering | MVVM layout, key files, fragile-test matrix | [engineering/architecture.md](engineering/architecture.md) |
| Operations | Apple Developer, CloudKit Production, TestFlight, release notes | [operations/release.md](operations/release.md), [operations/releases/](operations/releases/) |
| Backlog | Open engineering work and the decisions it waits on | [operations/backlog.md](operations/backlog.md) |
| Regression notes | Failures that changed a check or an upper layer | [lessons.md](lessons.md) |
| Public surface | Privacy policy (the App Store URL points here, so do not move it) | [privacy.md](privacy.md), `privacy.html` |

Build, lint and test: the `ios-verify` gate of the ios-dev Claude Code plugin, configured by
[`ios-verify.conf`](../ios-verify.conf); commands in [`AGENTS.md`](../AGENTS.md#commands). CI and
TestFlight tags: [ADR 0003](decisions/0003-ci-split.md), [ADR 0004](decisions/0004-tag-gated-testflight.md).
