# Legacy migration and cleanup

## Local SQLite

Older installs keep the same store files (`OneCart-private.sqlite` / `OneCart-shared.sqlite`). On first launch of a CloudKit build, unbound family spaces attach to the current iCloud profile and export to the private database.

`LegacyMigration` can also import a JSON snapshot (`onecart.app-state` / `onecart-backup.json`) when present on device.

Avatars and banners stay device-local — not migrated to CloudKit.

## Supabase → iCloud

- Supabase Auth users are **not** Apple / iCloud accounts; they cannot be imported as CloudKit logins.
- Only data present in the device local cache moves automatically.
- Full server-side row export needs a separate owner-led dump; then re-invite members with `CKShare`.

## Security: old Supabase project

`SupabaseServices.swift`, `supabase/`, and `invite-site/` are gone from `main`. A publishable key from commit `ebd4583` may still exist in git history.

1. In [Supabase Dashboard](https://supabase.com/dashboard) for project `<redacted>` — **rotate / revoke** the publishable key; pause or delete the project if unused.
2. History rewrite (`git filter-repo` + force-push to `main`) was **not** done automatically — requires explicit owner confirmation.
