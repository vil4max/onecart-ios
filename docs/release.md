# Release (owner runbook)

Bundle ID `com.vil555tim.onecart` · Team `BTHRDS7254` · Container `iCloud.com.vil555tim.onecart`.

## 1. Apple Developer

1. Attach iCloud container `iCloud.com.vil555tim.onecart`.
2. Enable **Sign in with Apple**, **iCloud (CloudKit)**, **Push Notifications**.
3. Recreate Development/Distribution profiles after capabilities.
4. Team in Xcode must match the project Team.
5. Entitlements (`CKSharingSupported`, SIWA, iCloud) are already in the project — unsigned Debug builds compile without App ID setup; signed install + real sync need the steps above.

## 2. CloudKit Production schema

Before TestFlight / App Store:

1. [CloudKit Console](https://icloud.developer.apple.com/) → container → Schema.
2. Confirm Development has all record types (see [architecture.md](architecture.md)).
3. **Deploy Schema Changes to Production**.
4. Re-run the two-device checklist on Production.

## 3. Two-device checklist

Physical devices, different iCloud accounts (simulator is UI/local Core Data only):

1. Signed Debug build on A and B.
2. On A: create household + items (including offline).
3. Go online → “Synced with iCloud”.
4. Invite → open iCloud share URL on B.
5. Family appears on B; edits sync both ways.
6. Remove member on A → B loses access.
7. Relaunch offline: local data opens; queued changes upload when back online.

## 4. TestFlight

### Preferred: Xcode Cloud → TestFlight

Not local Archive. ADP includes 25 compute hours/month. No GitHub Actions / fastlane in this repo.

**Prerequisites:** shared scheme `OneCart` with Archive; ASC app record; CloudKit Production schema; no `ci_scripts` needed.

```bash
xcodebuild -project OneCart/OneCart.xcodeproj -describeAllArchivableProducts -json
```

**First-time (Xcode UI):** push `main` → open `OneCart/OneCart.xcodeproj` → Report navigator → Cloud → Get Started → product `OneCart` / team `BTHRDS7254` → grant repo access → commit generated `OneCart/OneCart.xcodeproj/xcshareddata/xcodecloud/manifest.json`.

**Target workflow** (App Store Connect → Xcode Cloud → Manage Workflows):

| Field | Value |
|-------|-------|
| Repo | `https://github.com/vil4engineering/OneCart.git` |
| Project | `OneCart/OneCart.xcodeproj` |
| Start condition | Branch changes → `main` |
| Action 1 | Test — iOS, scheme `OneCart`, required |
| Action 2 | Archive — iOS, scheme `OneCart` → TestFlight (internal) |
| Post | Internal TestFlight → group **Friends&Family** |

After green build: set next build number if ASC expects `1`; confirm family Apple IDs in Friends&Family; owner sends `CKShare` link after install.

TestFlight builds: 90 days. Xcode Cloud artifacts: 30 days.

Docs: [Configuring your first Xcode Cloud workflow](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow).

### Fallback: local Archive

Only if Xcode Cloud is unavailable: bump `CURRENT_PROJECT_VERSION` → Product → Archive (scheme `OneCart`, Release) → Distribute → App Store Connect → TestFlight.

## 5. Public App Store (optional)

- Privacy Nutrition Labels: name, user ID, user content (lists), store geolocation — “App Functionality”, no tracking (`PrivacyInfo.xcprivacy` already in project).
- Screenshots: iPhone 6.7" / 6.5".
- Review notes: “Sign in with Apple required; family sharing via iCloud CKShare invite link in Settings”.

## 6. Not needed for this pet project

Own server, Supabase, GitHub Actions, fastlane, email/password auth, multi-cart UX (code can hold multiple spaces; UI hides creating a second group).

## 7. Ongoing

- Watch CloudKit quotas (fine for ~4 people).
- After Core Data model changes → deploy schema to Production again.
- Ship via Xcode Cloud (or local Archive fallback).
