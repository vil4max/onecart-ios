# OneCart

User-facing product name: **OneCart Family**. Repo / Xcode module / scheme stay **OneCart**.

One shared family cart on iOS: add what you need, mark items **Completed** at the store, and see purchases in **History by day** (overnight archive when you open the app). Sign in with Apple; sync and invites run through iCloud / CloudKit (`CKShare`).

## About this repo

OneCart Family is a production pet project, released on the [App Store](https://apps.apple.com/app/id6793219621) and maintained as a real product: Sign in with Apple, offline-first Core Data with CloudKit private and shared stores, `CKShare` invites, WidgetKit and App Intents, and XCTest regression suites for cart state, sharing, persistence, synchronization errors, and deletion recovery.

It is developed independently through an agentic SDLC: coding agents implement changes, while architecture decisions, code review, defect investigation, and release verification stay with the owner.

## Screenshots

<p>
  <img src="assets/store/screenshots/asc-6.5/01-welcome-dark.png" alt="Welcome" width="180" />
  <img src="assets/store/screenshots/asc-6.5/02-cart-dark.png" alt="Cart" width="180" />
  <img src="assets/store/screenshots/asc-6.5/03-history-dark.png" alt="History" width="180" />
  <img src="assets/store/screenshots/asc-6.5/04-account-dark.png" alt="Account" width="180" />
</p>

Store masters and ASC sizes: [`assets/store/`](assets/store/).

## Stack

- SwiftUI, iOS 26+
- Core Data via `NSPersistentCloudKitContainer`
- CloudKit private / shared databases
- `CKShare` link-join invites (`publicPermission = .readWrite`)
- Offline-first local SQLite stores

Bundle ID: `com.vil555tim.onecart`  
CloudKit container: `iCloud.com.vil555tim.onecart`

## Open in Xcode

Open **`OneCart/OneCart.xcodeproj`** (scheme `OneCart`).

For device / TestFlight: App ID capabilities and CloudKit Production — see [docs/operations/release.md](docs/operations/release.md).

## Layout

```text
.
├── OneCart/                 # App product
│   ├── OneCart.xcodeproj
│   ├── Application/         # App entry, AppSession, root + tabs
│   ├── Features/            # Feature UI + ViewModels
│   ├── Data/                # Persistence, CloudKit, Auth
│   ├── Shared/
│   ├── Resources/
│   └── Tests/
├── docs/                    # See docs/README.md
├── assets/                  # Brand / store masters (not in the app bundle)
├── Tooling/                 # Engineering Runtime — see Tooling/README.md
├── justfile                 # Thin shim → import Tooling/justfile
├── README.md
├── AGENTS.md
└── .gitignore
```

Native SwiftUI only — no web / Capacitor stack.

## Commands

```bash
brew bundle --file=Tooling/Brewfile
just doctor
just build
just test
just verify
```

Config: [`Tooling/runtime.yml`](Tooling/runtime.yml). Local overrides: `Tooling/runtime.local.yml.example` → `Tooling/runtime.local.yml`.

Install the repository pre-push hook once with `./scripts/install-hooks.sh`.
It runs smoke tests for branch updates and skips tag-only pushes and ref deletions.

## Docs

Start at [docs/README.md](docs/README.md) — architecture, product, release, legacy, review changelog.
