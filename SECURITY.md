# Security

## Supported versions

Security fixes apply to the latest App Store / TestFlight build of OneCart on the `main` branch.

## Reporting a vulnerability

Do **not** open a public GitHub issue for security reports that include exploit details or personal data.

Email the maintainer via the contact listed on the App Store listing for OneCart, or open a private report to repository admins if you have collaborator access.

Please include:

- Affected build / commit when known
- Steps to reproduce
- Impact (data exposure, wipe, share ACL, etc.)

## Scope notes

- Shopping data syncs via the user’s iCloud / CloudKit container; Apple’s CloudKit threat model applies.
- Profile photos are stored device-locally under the app Documents directory (`OneCartProfiles`), not in CloudKit.
- Sign in with Apple credentials are stored in the Keychain via `AppleSignInService`.
