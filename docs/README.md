# Docs

| Doc | Audience | Contents |
|-----|----------|----------|
| [architecture.md](architecture.md) | agents / contributors | MVVM layout, owner files (CartSync / bootstrap / content / cloud sync split), fragile-test matrix F1–F10, Core Data + CloudKit stores |
| [product.md](product.md) | product + agents | **Thesis**, living cart, Completed → overnight History by day, Household vs Apple Family |
| [release.md](release.md) | owner | Apple Developer, CloudKit Production, TestFlight / Xcode Cloud, two-device QA |
| [legacy.md](legacy.md) | owner | Pre-ASC wipe; SQLite reuse; Supabase cleanup |
| [review-changelog.md](review-changelog.md) | PR reviewer | Scoped `RCxx` / `NCxx` / `FUxx` checklist |
| [adr/0002-cloudkit-native-backend.md](adr/0002-cloudkit-native-backend.md) | archive | Why CloudKit (accepted decision) |

**Working agreement:** ship a reliable SIWA → one living cart → name-only add → mark Completed → overnight History → invite/sync loop before restoring Stores/catalog/price UX. Details in [product.md](product.md).

Engineering Runtime (just / Brewfile / host adapters): [`Tooling/README.md`](../Tooling/README.md).
