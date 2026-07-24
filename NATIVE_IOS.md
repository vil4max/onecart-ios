# OneCart iOS: Core Data + CloudKit

Нативный target `App` построен на SwiftUI — это единственный runtime OneCart (веб-прототип и Capacitor удалены). `NSPersistentCloudKitContainer` сохраняет offline-first поведение Core Data и синхронизирует данные через родной iCloud без отдельной учётной записи OneCart.

## Owner-файлы

- `PersistenceController.swift` — private/shared SQLite stores и их CloudKit scopes.
- `CloudKitServices.swift` — состояние iCloud-аккаунта, роли `CKShare`, приглашения и участники.
- `FamilySpaceRepository.swift` — локальные CRUD-операции и проверка разрешений shared records.
- `AppDelegate.swift` — приём системных CloudKit share invitations.
- `AppModel.swift` — запуск, выбранная семья, sync state и реакция на CloudKit events.
- `AppleSignInService.swift` — Sign in with Apple, Keychain-сессия.
- `SignInView.swift` — экран входа.
- `RootView.swift` — первое семейное пространство и основные вкладки.
- `SettingsView.swift` — участники, системная share-ссылка и управление семьёй.

## Хранилища и синхронизация

Используются два существующих файла, поэтому локальная база старой установки не переименовывается:

- `OneCart-private.sqlite` → CloudKit private database;
- `OneCart-shared.sqlite` → CloudKit shared database.

Новое семейное пространство и все его дочерние Core Data объекты назначаются в private store. После создания `CKShare` другой пользователь принимает системную iCloud-ссылку, и расшаренное пространство появляется в shared store. Изменения сохраняются локально сразу; CloudKit отправляет и принимает их при наличии сети.

## Аккаунт и профиль

Перед использованием приложения пользователь входит через **Sign in with Apple**. Учётные данные сохраняются в Keychain; при следующем запуске сессия восстанавливается автоматически.

Для синхронизации списков дополнительно требуется iCloud-аккаунт устройства: приложение проверяет `CKContainer.accountStatus` после входа через Apple. Формы email/password отсутствуют.

Отображаемое имя и медиа профиля являются настройками этого устройства. Аватар и баннер не отправляются в CloudKit и намеренно не входят в миграцию.

## Семейный доступ

Владелец создаёт системную `CKShare`-ссылку из экрана семьи. Получатель открывает ссылку и подтверждает доступ системным интерфейсом iCloud. Роль владельца определяется private store, роль участника — shared store. Удаление участника изменяет список участников `CKShare`; выход участника очищает принятую shared zone на его устройстве.

Старые `onecart://invite/...` токены, отдельный invite endpoint и срок жизни в 14 дней больше не используются.

## Настройка Apple Developer

Для App ID `com.vil555tim.onecart` нужно:

1. Создать или подключить iCloud container `iCloud.com.vil555tim.onecart`.
2. Включить **Sign in with Apple**.
3. Включить iCloud с сервисом CloudKit.
4. Включить Push Notifications — они нужны для фоновых изменений CloudKit.
5. Пересоздать Development/Distribution provisioning profiles после добавления capabilities.
6. Убедиться, что выбранная Team совпадает с Team проекта в Xcode.
7. После создания схемы в Development открыть CloudKit Console и развернуть её в Production перед TestFlight или Distribution-сборкой.

В проект уже добавлены Sign in with Apple, iCloud/CloudKit entitlements, `CKSharingSupported` и обработчик принятия share metadata. До настройки App ID сборка без подписи компилируется, но подписанная установка и реальная синхронизация работать не будут.

## Перенос данных со старой установки

На устройстве с существующим приложением прежние локальные записи остаются в тех же SQLite stores. После первого запуска новой версии непривязанные семейные пространства закрепляются за текущим iCloud-профилем, а persistent container начинает их экспортировать в private database.

Это переносит только данные, которые реально присутствуют в локальном кэше устройства. Для полного серверного переноса всех Supabase rows сначала нужен административный экспорт базы. Импортировать Supabase Auth users как iCloud users невозможно: соответствия между чужими email и приватными iCloud identities нет. Практический путь для семей — перенести данные владельца, затем заново отправить участникам системные `CKShare`-приглашения.

## Проверка на двух устройствах

1. Установить подписанную Debug-сборку на два физических устройства с разными iCloud-аккаунтами.
2. На устройстве A создать семью и несколько товаров, в том числе офлайн.
3. Подключить сеть и дождаться статуса «Синхронизировано с iCloud».
4. Создать приглашение и открыть iCloud share URL на устройстве B.
5. Убедиться, что семья появилась на B и изменения доходят в обе стороны.
6. Удалить участника на A и проверить потерю доступа на B.
7. Повторить запуск без сети: локальные данные должны открываться, а новые изменения — отправиться после восстановления сети.

Симулятор подходит для проверки UI и локального Core Data, но полноценный `CKShare` flow следует проверять на физических устройствах.

## CloudKit Production schema

Container: `iCloud.com.vil555tim.onecart`. Record types (из Core Data `OneCartCoreDataV4`):

`FamilySpace`, `Store`, `ShoppingList`, `Product`, `PurchaseHistory`, `HistoryItem`, плюс системный `CKShare` на корневом `FamilySpace`.

Перед TestFlight / App Store:

1. Открыть [CloudKit Console](https://icloud.developer.apple.com/) → container → Schema.
2. Убедиться, что все типы есть в Development.
3. **Deploy Schema Changes to Production**.
4. Повторить двухдевайсный чеклист выше уже на Production-окружении.

## Безопасность: legacy Supabase

Файлы `SupabaseServices.swift`, `supabase/` и `invite-site/` удалены из текущего `main`. Publishable key из старого коммита `ebd4583` всё ещё виден в git history.

Обязательно:

1. В [Supabase Dashboard](https://supabase.com/dashboard) для проекта `<redacted>` — **rotate / revoke** publishable key и при возможности поставить проект на pause или удалить.
2. History rewrite (`git filter-repo` + force-push на `main`) намеренно не выполнялся автоматически: репозиторий private, но force-push на `main` требует явного ручного подтверждения владельца.

