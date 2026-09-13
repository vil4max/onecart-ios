# OneCart Family 1.2

## Candidate

- Local version/build: **1.2 (1)** for the app and widget extension, Debug and Release; iPhone only.
- Previous App Store version: **1.1 (90)**, confirmed Ready for Distribution in App Store Connect on September 13, 2026.
- Scope: immediate language switching in cart progress, item attribution, member roles, history and accessibility labels; duplicate-item protection and cart interaction improvements already merged after build 90.
- Xcode Cloud assigns the uploaded build number independently of the local build setting. Select the build from the verified release commit.
- Local verification passed on September 13, 2026: `just verify` (200 XCTest and 13 Swift Testing tests), Release simulator build, and app/widget version, iPhone device-family and privacy-manifest checks in both configurations.
- Simulator regression confirmed Russian/Ukrainian member roles, Ukrainian cart counts, item and history attribution, composer and suggestion accessibility labels. The app language preference was restored to System.
- Signed two-device CloudKit, account deletion and widget interaction checks remain device-only follow-up work. Upload and App Review submission status must be checked in App Store Connect.

## What’s New — English

- Adding the same product again now finds the existing item instead of creating a duplicate.
- Smoother cart animations and improved inline editing and completion feedback.
- Fixed text that stayed in the previous language after changing the app language, including cart progress, item details and member roles.
- Improved language switching for purchase history and accessibility labels.

## What’s New — Russian

- При повторном добавлении товара приложение находит существующую позицию вместо создания дубликата.
- Улучшены анимации корзины, редактирование товаров и отображение завершённых покупок.
- Исправлены тексты, которые оставались на прежнем языке после смены языка приложения: прогресс корзины, подписи товаров и роли участников.
- Улучшено переключение языка в истории покупок и подписях для VoiceOver.

## What’s New — Ukrainian

- Під час повторного додавання товару застосунок знаходить наявну позицію замість створення дубліката.
- Поліпшено анімації кошика, редагування товарів і відображення завершених покупок.
- Виправлено тексти, які залишалися попередньою мовою після зміни мови застосунку: прогрес кошика, підписи товарів і ролі учасників.
- Поліпшено перемикання мови в історії покупок і підписах для VoiceOver.

## TestFlight — What to Test

- Switch English → Russian → Ukrainian → System without restarting. Check cart counts, creator/buyer captions, member roles, history attribution and VoiceOver labels.
- Add and rename items, retry an existing name with different casing or surrounding whitespace, mark/unmark a purchase and delete an unpurchased item.
- Check that purchased items remain in Completed on the same day and appear in History after opening the app on a later day.
- Continue signed-device CloudKit and widget checks from [the release runbook](release.md#3-two-device-checklist); simulator checks do not replace them.
