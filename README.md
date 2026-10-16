# OneCart Family

One shared shopping cart for the whole family: anyone adds what is needed, the shopper checks
items off in the store, and everyone follows the progress and sees what was bought, day by day.

Available on the [App Store](https://apps.apple.com/app/id6793219621) as OneCart Family.

<p><img src="assets/store/screenshots/asc-6.9/02-cart.png" alt="The shared cart" width="240" /></p>

## Features

- One living family cart: add items by name, mark them **Completed** at the store.
- **History by day**: items completed on an earlier day move to History when the app opens.
- Family sharing through a `CKShare` invite link, with member list, leave and revoke-invite.
- Sign in with Apple; sync runs through iCloud / CloudKit and works offline-first.
- Home Screen and Lock Screen widgets, a shopping-trip Live Activity, and Siri / Shortcuts
  actions to add items, read what is left and start a trip.
- Quick suggestion chips ranked by purchase history; local notifications for family activity.
- English, Russian and Ukrainian.

**Stack:** Swift 6, SwiftUI, Core Data with CloudKit (private and shared stores, `CKShare`
invites), WidgetKit, Live Activities, App Intents, Foundation Models; iOS 27+, iPhone only.

User-facing product name: **OneCart Family**. The repository, Xcode module and scheme are
named **OneCart**.

### Screenshots

<p>
  <img src="assets/store/screenshots/asc-6.9/01-welcome.png" alt="Welcome" width="180" />
  <img src="assets/store/screenshots/asc-6.9/02-cart.png" alt="Cart" width="180" />
  <img src="assets/store/screenshots/asc-6.9/03-history.png" alt="History" width="180" />
  <img src="assets/store/screenshots/asc-6.9/04-settings.png" alt="Settings" width="180" />
</p>

Store masters and App Store Connect sizes: [`assets/store/`](assets/store/).

## Requirements and tests

Behavior is specified as numbered requirements (`REQ-AREA-NNN`) in
[docs/requirements/product.md](docs/requirements/product.md). Each requirement lists the named
tests that prove it in the [coverage matrix](docs/requirements/product.md#coverage), and the
tests cite the same IDs in their names. Design choices are recorded in
[docs/decisions/](docs/decisions/).

## Building

Bundle ID: `com.vil555tim.onecart`  
CloudKit container: `iCloud.com.vil555tim.onecart`

Open **`OneCart/OneCart.xcodeproj`** (scheme `OneCart`) in Xcode 27 or later. The scheme's
Test action runs the unit tests and the UI smoke tests.

The command-line gate is `ios-verify` from the ios-dev Claude Code plugin, configured by
[`ios-verify.conf`](ios-verify.conf). It needs Xcode and SwiftLint at the version in
[`.swiftlint-version`](.swiftlint-version) (`ios-verify` warns on a mismatch); swift-format ships
with Xcode.

```bash
ios-verify              # project checks, lint, build, unit and UI smoke tests
ios-verify lint --all   # swift-format and SwiftLint over every Swift file
ios-verify run-sim      # the seeded demo cart on the simulator
```

Without the plugin, the GitHub Actions `Tests` workflow
([`.github/workflows/tests.yml`](.github/workflows/tests.yml)) shows the same checks as plain
`xcrun swift-format`, `swiftlint` and `xcodebuild` commands, using the committed
`.swift-format`, `.swiftlint.yml` and `.swiftlint.baseline.json`. The repository has no git
hooks.

For device builds and TestFlight, including App ID capabilities and the CloudKit Production
schema, see [docs/operations/release.md](docs/operations/release.md).

## Layout

```text
.
├── OneCart/                 # App product
│   ├── OneCart.xcodeproj
│   ├── Application/         # App entry, AppSession, root + tabs
│   ├── Features/            # Feature UI + ViewModels
│   ├── Data/                # Persistence, CloudKit, Auth
│   ├── Shared/
│   ├── OneCartWidgets/      # Widgets and Live Activity
│   ├── Resources/
│   ├── Tests/               # Unit tests
│   ├── OneCartUITests/      # UI smoke tests
│   └── ci_scripts/          # Xcode Cloud and TestFlight tag scripts
├── docs/                    # See docs/README.md
├── assets/                  # Brand / store masters (not in the app bundle)
├── ios-verify.conf          # Gate configuration
├── README.md
└── AGENTS.md
```

Native SwiftUI only; there is no web or cross-platform stack.

## Documentation

Start at [docs/README.md](docs/README.md): core goals, requirements, decisions, architecture,
release runbook and privacy policy.

## License

Released under the MIT License; see [LICENSE](LICENSE).
