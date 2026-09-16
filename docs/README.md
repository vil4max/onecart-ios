# Docs

Spec pyramid: each layer details the one above it. Change starts at the
highest affected layer; evidence from operations flows back up.

| Layer | Question | Source |
|---|---|---|
| L0 core | Goal, language, priorities, constraints | [core.md](core.md) (approved 2026-09-16) |
| L1 requirements | Thesis, living cart, Completed → History, membership, widgets | [requirements/product.md](requirements/product.md) |
| L1 decisions | Why CloudKit; which CI owns tests vs TestFlight | [decisions/0002-cloudkit-native-backend.md](decisions/0002-cloudkit-native-backend.md), [decisions/0003-ci-split.md](decisions/0003-ci-split.md) |
| L2 specs | Which tests prove the requirements? | `OneCart/Tests/` — name tests with `REQ-<AREA>-NNN` |
| Engineering | MVVM layout, owner files, fragile-test matrix; PR review checklist | [engineering/architecture.md](engineering/architecture.md), [engineering/review-changelog.md](engineering/review-changelog.md) |
| Operations | Apple Developer, CloudKit Production, TestFlight, release notes | [operations/release.md](operations/release.md), [operations/releases/](operations/releases/) |
| Planning | Legacy migration and cleanup | [planning/legacy-migration.md](planning/legacy-migration.md) |
| Lessons | Failures that changed a check or an upper layer | [lessons.md](lessons.md) |
| Public surface | Privacy policy (App Store URL points here — do not move) | [privacy.md](privacy.md), `privacy.html` |

Engineering Runtime (just / Brewfile / host adapters): [`Tooling/README.md`](../Tooling/README.md).
