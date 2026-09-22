# Store / TestFlight visuals

## App Review attachment

The physical-device Delete Account recording (~21s, 1290×2796, HEVC, app **1.0 (84)**) is not
stored here: it shows the owner's Apple Account name and photo. The owner keeps it outside the
repository and attaches it under App Review Information.

## App Store Connect: iPhone 6.9" (1320 × 2868)

Current set for 1.6.0, light theme, captured on 2026-09-22 from the iOS 26/27 redesign (native
lists, glass add button, progress at the top of the cart, Settings grouped into cart, look & feel
and account; cart and Settings retaken after the owner's feedback on build 116). English files are in `screenshots/asc-6.9/` (the repository README shows
them); Russian files with the same names are in `screenshots/asc-6.9/ru/`. Version 1.5.0 was
submitted with the older 1.0-era set; these replace it in the 1.6.0 version record.

| # | File | Screen |
|---|------|--------|
| 1 | `01-welcome.png` | Welcome + Sign in with Apple |
| 2 | `02-cart.png` | Cart |
| 3 | `03-history.png` | History |
| 4 | `04-settings.png` | Settings |

How the set is made (Debug build, `just run-sim`, the session's own simulator):

- Device iPhone 17 on iOS 27 (1206 × 2622), scaled to 1320 × 2868; the aspect ratios
  differ by less than 0.1 %.
- Status bar 09:41, full battery (`xcrun simctl status_bar … override`).
- Launch arguments `-AppleLanguages (en|ru) -AppleLocale en_US|ru_RU -oneCartDemoUI` plus
  `-oneCartDemoRole welcome` for the welcome screen, or `-oneCartDemoRole owner -oneCartDemoTab
  cart|history|account`. The demo UI hides the Debug-only test-account button and seeds items in
  the device language, so reinstall the app before switching languages.
- Allow the notification prompt once after each install; it appears a few seconds after launch.
- Guest / member of someone else's cart: `-oneCartDemoUI -oneCartDemoRole member` (Sam on
  **Alex's Cart**, Leave / no Rename / no Revoke).
