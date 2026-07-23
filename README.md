# OneCart

OneCart — нативное SwiftUI-приложение для общих семейных покупок. Данные хранятся локально в Core Data и автоматически синхронизируются через iCloud/CloudKit. Отдельной регистрации, email и пароля в приложении нет: используется iCloud-аккаунт устройства.

## Технологии

- SwiftUI, iOS 15+
- Core Data через `NSPersistentCloudKitContainer`
- CloudKit private/shared databases
- `CKShare` для приглашений и управления семейным доступом
- локальный offline-first кэш в двух SQLite stores

Bundle ID приложения: `com.vil555tim.onecart`.
CloudKit container: `iCloud.com.vil555tim.onecart`

## Открытие проекта

Откройте [ios/App/App.xcodeproj](ios/App/App.xcodeproj) в Xcode. Перед запуском на устройстве включите для App ID возможности iCloud/CloudKit и Push Notifications, привяжите CloudKit container и обновите provisioning profile.

Подробности архитектуры, настройки и проверки на двух iCloud-аккаунтах находятся в [NATIVE_IOS.md](NATIVE_IOS.md).

## Структура репозитория

Единственный runtime — нативный target в [ios/App/App.xcodeproj](ios/App/App.xcodeproj). React/Vite/Capacitor-прототип удалён; веб-кода в репозитории нет.

## Миграция со старого backend

Supabase SDK, Auth UI, Realtime/RPC sync, Edge Functions и SQL migrations удалены. Локальные данные существующей установки используют прежние SQLite-файлы и после обновления загружаются в private database текущего iCloud-аккаунта. `LegacyMigration` также умеет импортировать старый JSON-снимок (`onecart.app-state` / `onecart-backup.json`), если он есть на устройстве.

Supabase Auth-пользователи не являются Apple/iCloud-аккаунтами и не могут быть импортированы как логины CloudKit. Серверные данные других пользователей требуют отдельного защищённого экспорта и последующего переноса владельцами в их iCloud либо повторного приглашения через `CKShare`. Аватары и баннеры остаются только на устройстве и в серверную миграцию не входят.
