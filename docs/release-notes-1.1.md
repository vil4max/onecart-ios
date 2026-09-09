# OneCart Family 1.1

## Candidate

- Local version/build: **1.1 (2)**, app and widget extension, Debug and Release. All targets support iPhone only, matching published version 1.0 (84).
- Scope: reliability fixes in `0842c07..d85ab0a`; this is an audited change range, not a verified previous App Store release boundary.
- Candidate commit `71a8441` is pushed to `origin/main`.
- App Store Connect version **1.1** is created with English and Russian release notes and automatic release after approval. The Russian description and support URL are updated.
- Xcode Cloud build **89** (`71a8441`) succeeded, but declared iPad support unintentionally. It is superseded by the iPhone-only correction; do not submit build 89. Xcode Cloud assigns the uploaded build number independently of the local build setting.
- App Review contacts are filled. Submission is pending the replacement iPhone-only build. No release tag or public release has been made for this candidate.

## What’s New — English

- Improved cart recovery after reinstalling and switching to a shared family cart.
- Fixed invite links reopening unexpectedly after they were revoked.
- Fixed duplicate purchases appearing in History.
- Improved purchase updates and progress counts in widgets, and cleared widget data on sign-out.
- Improved recovery when account deletion is interrupted.

## What’s New — Russian

- Улучшено восстановление корзины после переустановки и переключение на общую семейную корзину.
- Исправлено неожиданное повторное открытие отозванных ссылок-приглашений.
- Устранены дубли покупок в истории.
- Улучшены отметки покупок и счётчики в виджетах; данные виджета очищаются при выходе из аккаунта.
- Улучшено восстановление после прерывания удаления аккаунта.

## What’s New — Ukrainian

- Поліпшено відновлення кошика після перевстановлення та перехід до спільного сімейного кошика.
- Виправлено неочікуване повторне відкриття відкликаних посилань-запрошень.
- Усунено дублікати покупок в історії.
- Поліпшено позначення покупок і лічильники у віджетах; дані віджета очищуються після виходу з облікового запису.
- Поліпшено відновлення після переривання видалення облікового запису.

## TestFlight — What to Test

- Restore an existing cart on a fresh installation while adding items before synchronization finishes; both old and new items should remain available.
- Join another family cart without removing the previous family’s data. Revoke an invite, rename or relaunch the app, and confirm the link stays closed until explicitly shared again.
- Mark the same purchase completed on two devices and reopen the app the next day; History should show the purchase once.
- Mark purchases from a widget with the app closed, retry after an interrupted save, and check progress counts on a cart larger than the widget’s visible list.
- Sign out and confirm widget data clears. Test interrupted account deletion and retry with disposable test accounts only.

## Release validation and delivery

The bumped **1.1 (1)** candidate passed `just verify` (197 XCTest tests and the Swift Testing suites), a Release simulator build, and independent release review. Both built bundles report **1.1 (1)** and include their privacy manifests. The pre-bump source baseline also launched on iPhone 17 Simulator and rendered the test cart. This is not a signed-device widget or two-account CloudKit result.

Before publication:

1. Local candidate verification is complete; rerun it if the candidate changes.
2. App Store Connect version 1.1 and its localized metadata are prepared. App Review contacts are filled.
3. Upload and validate the replacement iPhone-only build, then select it for version 1.1.
4. Complete the signed-device checks in [the release runbook](release.md#3-two-device-checklist), especially terminated-app widget actions and two-account CloudKit recovery.
5. Use the matching localized notes, select the validated build, and submit the version after the release decision. Tag the final shipped commit rather than this unvalidated candidate.
