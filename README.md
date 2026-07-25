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

Before device / TestFlight runs, enable Sign in with Apple, iCloud / CloudKit, and Push Notifications on the App ID, attach the CloudKit container, and refresh provisioning profiles.

Details, two-account checks, and TestFlight notes: [NATIVE_IOS.md](NATIVE_IOS.md).

TestFlight releases go through **Xcode Cloud**. Point the workflow at **`OneCart/OneCart.xcodeproj`** (not the old `ios/App/App.xcodeproj`). Local Archive is fallback only.

## Layout

| Path | Responsibility |
|------|----------------|
| `OneCart/` | Xcode project, app sources, tests |
| `OneCart/OneCart.xcodeproj` | Project / scheme `OneCart` |
| `OneCart/Application/` | App entry, `AppSession`, root UI |
| `OneCart/Features/` | Feature UI + ViewModels |
| `OneCart/Data/` | Persistence, CloudKit, Auth, Migration |
| `OneCart/Shared/` | Cross-feature helpers |
| `OneCart/Resources/` | Assets, Info.plist, entitlements, String Catalog |
| `OneCart/Tests/` | Unit tests (`OneCartTests`) |
| `docs/` | Architecture, product flow, review changelog |
| `assets/` | Brand / store masters (not in the app bundle) |
| `Tooling/` | Engineering Runtime host adapters (not CloudKit) |

Native SwiftUI only — no web / Capacitor stack in this repo.

## Commands

```bash
just doctor
just build
just test
just verify
```

## Review

PR review starts at [docs/review-changelog.md](docs/review-changelog.md).

## Legacy migration

Local SQLite from older installs is reused. `LegacyMigration` can also import a JSON snapshot (`onecart.app-state` / `onecart-backup.json`) when present on device.

Former Supabase Auth users are not Apple / iCloud accounts and cannot be imported as CloudKit logins. Server-side data for other users needs a separate owner-led export into iCloud or a fresh `CKShare` invite. Avatars and banners stay device-local.
