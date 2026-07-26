# Docs

| Doc | Audience | Contents |
|-----|----------|----------|
| [architecture.md](architecture.md) | agents / contributors | MVVM layout, owner files, Core Data + CloudKit stores, stability-first shell |
| [product.md](product.md) | product + agents | **Stability first**, cut rationale, user flow, Household vs Apple Family |
| [release.md](release.md) | owner | Apple Developer, CloudKit Production, TestFlight / Xcode Cloud, two-device QA |
| [legacy.md](legacy.md) | owner | Local SQLite reuse, Supabase cleanup |
| [review-changelog.md](review-changelog.md) | PR reviewer | Scoped `RCxx` / `NCxx` / `FUxx` checklist |
| [adr/0002-cloudkit-native-backend.md](adr/0002-cloudkit-native-backend.md) | archive | Why CloudKit (accepted decision) |

**Working agreement:** ship a reliable SIWA → one cart → add items → invite/sync loop before restoring Stores/catalog/Settings prefs UX. Details in [product.md](product.md) § Priority.

Engineering Runtime (just / Brewfile / host adapters): [`Tooling/README.md`](../Tooling/README.md).
