# Legacy migration and cleanup

## Pre–App Store

There is no App Store install base yet. JSON / `onecart.app-state` legacy import and rename of «Наша семья» were removed.

For a clean start on TestFlight devices: delete the app (there is no Recreate/Delete cart in UX). Owner **Revoke invite** only closes the door for new joins on the same durable cart.

## Local SQLite

Store files stay `OneCart-private.sqlite` / `OneCart-shared.sqlite` (no rename). Unbound private family spaces still attach to the signed-in Apple ID on first CloudKit launch.

Avatars and banners stay device-local — not migrated to CloudKit.

## Supabase → iCloud (historical)

- Supabase Auth users are not Apple / iCloud accounts.
- Server-side Supabase row export is out of scope; re-invite members with `CKShare` after a fresh cart.

## Security: old Supabase project

`SupabaseServices.swift`, `supabase/`, and `invite-site/` are gone from `main`. A publishable key from commit `ebd4583` may still exist in git history.

1. In [Supabase Dashboard](https://supabase.com/dashboard) for the retired OneCart project — rotate / revoke the publishable key; pause or delete the project if unused.
2. History rewrite requires explicit owner confirmation.
