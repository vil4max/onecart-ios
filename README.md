# OneCart

OneCart — нативное iOS-приложение на SwiftUI для общих семейных покупок. Пользователь регистрируется по имени, email и паролю; семейные пространства, приглашения и синхронизация работают через Supabase. Core Data остаётся локальной offline-first копией, поэтому продукты можно добавлять без сети.

## Нативное приложение

- Xcode-проект: `ios/App/App.xcodeproj`
- Схема: `App`
- Bundle identifier: `com.vil55tim.onecart`
- Минимальная версия iOS: 15.0
- Backend: Supabase Auth, Postgres, Row Level Security и Realtime
- Локальное хранилище: Core Data
- Supabase Swift SDK: 2.46.0, закреплён точной версией

Откройте `ios/App/App.xcodeproj`, выберите свою Apple Development Team и запускайте обычную схему `App`. iCloud, CloudKit, Push Notifications и платная Apple Developer Program для синхронизации не требуются. Для установки приложения на собственный iPhone по-прежнему действуют стандартные правила подписи Xcode.

Supabase уже настроен в `SupabaseServices.swift` с publishable key. Service-role key в приложение не добавляется. Схема сервера находится в `supabase/migrations/`, а публичный HTTPS-переход из Telegram/Сообщений в установленное приложение — в `supabase/functions/onecart-invite/`.

Подробная архитектура и сценарий проверки двух аккаунтов описаны в [NATIVE_IOS.md](NATIVE_IOS.md).

## Проверка

Сборка приложения без подписи:

```bash
cd ios/App
xcodebuild \
  -project App.xcodeproj \
  -scheme App \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Компиляция unit-тестов:

```bash
cd ios/App
xcodebuild \
  -project App.xcodeproj \
  -scheme App \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing
```

## React/Vite-прототип

Каталоги `src/`, `public/` и npm-зависимости сохранены только как визуальный и продуктовый референс. Они не входят в native target и не управляют данными iOS-приложения.

## Брендовые assets

- Мастер app icon: `assets/brand/onecart-app-icon-1024.png`
- Мастер launch screen: `assets/brand/onecart-launch-master.png`
- Xcode AppIcon: `ios/App/App/Assets.xcassets/AppIcon.appiconset/`
- Xcode Splash: `ios/App/App/Assets.xcassets/Splash.imageset/`
