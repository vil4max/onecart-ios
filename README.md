# OneCart

Family shopping list for up to four people on iOS. One Welcome screen with **Sign in with Apple**; the shared cart syncs through iCloud / CloudKit. The first signed-in owner gets a Household cart; others join via a private invite link (`CKShare`).

## Stack

- SwiftUI, iOS 15+
- Core Data via `NSPersistentCloudKitContainer`
- CloudKit private / shared databases
- Private `CKShare` invites (`publicPermission = .none`)
- Offline-first local SQLite stores

Bundle ID: `com.vil555tim.onecart`  
CloudKit container: `iCloud.com.vil555tim.onecart`

## Open in Xcode

Open **`OneCart/OneCart.xcodeproj`** (scheme `OneCart`).

For device / TestFlight: App ID capabilities and CloudKit Production — see [docs/release.md](docs/release.md).

## Layout

```text
.
├── OneCart/                 # App product
│   ├── OneCart.xcodeproj
│   ├── Application/         # App entry, AppSession, root UI
│   ├── Features/            # Feature UI + ViewModels
│   ├── Data/                # Persistence, CloudKit, Auth, Migration
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

## Docs

Start at [docs/README.md](docs/README.md) — architecture, product, release, legacy, review changelog.
