# Store / TestFlight visuals

## App Review attachment

The physical-device Delete Account recording (~21s, 1290×2796, HEVC, app **1.0 (84)**) is not
stored here: it shows the owner's Apple Account name and photo. The owner keeps it outside the
repository and attaches it under App Review Information.

## App Store Connect: iPhone 6.9" (1320 × 2868)

Current set, light theme, English (app `developmentRegion = en`). The repository
README shows these files.

| # | File in `screenshots/asc-6.9/` | Screen |
|---|--------------------------------|--------|
| 1 | `01-welcome.png` | Welcome + Sign in with Apple |
| 2 | `02-cart.png` | Cart |
| 3 | `03-history.png` | History |
| 4 | `04-settings.png` | Settings |

## App Store Connect: iPhone 6.5" (1284 × 2778)

Earlier capture of the same four screens (`01-welcome.png` … `04-account.png`) in both
themes. It predates the Settings tab and the Completed section; recapture before
uploading it again.

Folders: [`screenshots/asc-6.5/dark/`](screenshots/asc-6.5/dark/),
[`screenshots/asc-6.5/light/`](screenshots/asc-6.5/light/). Raw simulator captures:
[`screenshots/raw/`](screenshots/raw/) (`en-*`).

The 6.5" set was captured with sim language `en`, status bar 09:41, iPhone 16 Plus → resized to **1284 × 2778**.

Demo launch args:

- Owner (default): `-oneCartDemoUI` and optional `-oneCartDemoTab cart|history|account`
- Guest / member of someone else’s cart: `-oneCartDemoUI -oneCartDemoRole member` (Sam on **Alex's Cart**, Leave / no Rename / no Revoke)
