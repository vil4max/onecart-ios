# OneCart iOS: Core Data + CloudKit

Нативный target `App` построен на SwiftUI — это единственный runtime OneCart (веб-прототип и Capacitor удалены). `NSPersistentCloudKitContainer` сохраняет offline-first поведение Core Data и синхронизирует данные через родной iCloud без отдельной учётной записи OneCart.

## Owner-файлы

- `PersistenceController.swift` — private/shared SQLite stores и их CloudKit scopes.
- `CloudKitServices.swift` — состояние iCloud-аккаунта, роли `CKShare`, приглашения и участники.
- `FamilySpaceRepository.swift` — локальные CRUD-операции и проверка разрешений shared records.
- `AppDelegate.swift` — приём системных CloudKit share invitations.
- `AppModel.swift` — запуск, выбранная семья, sync state и реакция на CloudKit events.
- `AppleSignInService.swift` — Sign in with Apple, Keychain-сессия.
- `WelcomeView.swift` — единый экран: Sign in with Apple + подключение iCloud.
- `RootView.swift` — запуск, welcome или основные вкладки.
- `SettingsView.swift` — участники, системная share-ссылка и управление семьёй.

## Хранилища и синхронизация

Используются два существующих файла, поэтому локальная база старой установки не переименовывается:

- `OneCart-private.sqlite` → CloudKit private database;
- `OneCart-shared.sqlite` → CloudKit shared database.

Новое семейное пространство и все его дочерние Core Data объекты назначаются в private store. После создания `CKShare` другой пользователь принимает системную iCloud-ссылку, и расшаренное пространство появляется в shared store. Изменения сохраняются локально сразу; CloudKit отправляет и принимает их при наличии сети.

## Аккаунт и профиль

Один экран **WelcomeView**: Sign in with Apple → «Подключаем семейную корзину…» → главный экран. Ошибки iCloud показываются на том же экране с кнопкой «Повторить».

После первого входа приложение автоматически создаёт семейное пространство «Наша семья» с общим списком покупок. Отдельный онбординг «Создайте группу» не нужен.

Учётные данные Apple ID хранятся в Keychain. Для синхронизации требуется iCloud на устройстве (`CKContainer.accountStatus`). Формы email/password отсутствуют.

Отображаемое имя и медиа профиля являются настройками этого устройства. Аватар и баннер не отправляются в CloudKit и намеренно не входят в миграцию.

## Семейный доступ (4 человека)

Модель: **одна корзина на семью** через CloudKit Share. Apple Family (Семейный доступ) сам по себе корзину не объединяет — нужна ссылка-приглашение из приложения.

### Онбординг

На welcome-экране выбирается роль:

- **Создаю корзину для семьи** — после входа автоматически создаётся «Наша семья».
- **Меня пригласили** — личная корзина не создаётся; экран ждёт, пока пользователь откроет CKShare-ссылку.

### Принятие приглашения, если уже есть своя корзина

1. Сначала принимается CloudKit share (до автосоздания новой корзины).
2. Пустая стартовая личная корзина («Наша семья» без товаров) **удаляется автоматически**.
3. Если в личной корзине уже есть товары — показывается sheet:
   - перенести товары в семейную;
   - использовать только семейную (личная архивируется);
   - оставить личную (для редких случаев).

### Подключение участников

1. Владелец: Настройки → Участники → Пригласить → ссылка в семейный чат.
2. Участник: «Меня пригласили» → Sign in with Apple → открыть ссылку → Принять в iCloud.
3. У всех четверых один список; изменения синхронизируются через CloudKit.

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

## Выпуск в App Store (pet project)

Минимальный путь для семейного приложения без бэкенда:

### 1. Apple Developer

- Платная программа ($99/год), Team `BTHRDS7254`.
- App ID `com.vil555tim.onecart`: Sign in with Apple + iCloud (CloudKit) + Push.
- Provisioning profiles пересоздать после capabilities.

### 2. CloudKit Production

Обязательно до TestFlight: [CloudKit Console](https://icloud.developer.apple.com/) → Deploy Schema to Production.

### 3. TestFlight (внутренняя семья)

#### Preferred path: Xcode Cloud → TestFlight

Предпочтительный путь — [Xcode Cloud](https://developer.apple.com/xcode-cloud/get-started/), а не локальный Archive upload. В ADP входит 25 compute hours в месяц. GitHub Actions и fastlane в этом репозитории не используются (как в regional-check).

##### Repo prerequisites (уже выполнены)

- Shared scheme `App` с Archive (`buildForArchiving = YES`)
- Archivable product: `com.vil555tim.onecart` / team `BTHRDS7254`
- App Store Connect app record для этого bundle ID
- CloudKit Production schema (см. выше)
- `ci_scripts` не нужны (нет сторонних package installs)

Проверка локально:

```bash
xcodebuild -project ios/App/App.xcodeproj -describeAllArchivableProducts -json
```

##### First-time setup (Xcode UI)

Нужна роль Account Holder, Admin, App Manager, или Developer/Marketing с правом Create Apps.

1. Запушить `main` в GitHub (`vil4engineering/OneCart`).
2. Открыть `ios/App/App.xcodeproj` в Xcode 15+.
3. Report navigator → Cloud → Get Started.
4. Выбрать product `App`, team `BTHRDS7254`.
5. Выдать Xcode Cloud доступ к Git-репозиторию.
6. Start Build, затем в App Store Connect → Xcode Cloud → **Управление рабочими процессами** выставить workflow **точно как в Regional Check** (см. ниже).

После первого Get Started Xcode создаст `ios/App/App.xcodeproj/xcshareddata/xcodecloud/manifest.json` — закоммитить его в репозиторий.

Docs: [Configuring your first Xcode Cloud workflow](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow).

##### Целевой workflow (зеркало Regional Check)

В App Store Connect → OneCart → Xcode Cloud → Управление рабочими процессами:

| Поле | Значение |
|------|----------|
| Основной репозиторий | `https://github.com/vil4engineering/OneCart.git` |
| Проект или рабочее пространство | `ios/App/App.xcodeproj` |
| Среда → Xcode | Currently Xcode (как у Regional Check) |
| Среда → macOS | Currently macOS (как у Regional Check) |
| Очистка | без восстановления DerivedData / кэша сборок |
| Переменные среды | нет |
| Начальные условия | **Изменения ветки** → ветка `main` |
| Автоотмена сборок | включена (новая сборка на той же ветке отменяет текущие/ожидающие) |
| Файлы и папки | любой изменённый файл |
| Действие 1 | **Тестирование — iOS**, схема `App`, обязательно для прохождения, параметр «Тестировать (настройки схемы)», 1 destination |
| Действие 2 | **Архивирование — iOS**, схема `App`, подготовка к распространению: **TestFlight (только внутреннее тестирование)** |
| Последующие действия | **Внутреннее тестирование TestFlight — iOS**, артефакт Archive - iOS, группа **Friends&Family** (или та же семейная группа, что у Regional Check) |

После зелёного билда:

1. Если ASC ждёт build `1`, выставить next Xcode Cloud build number на `2+`: [Setting the next build number](https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds).
2. TestFlight → Internal Testing → Friends&Family → убедиться, что все семейные Apple ID в группе.
3. Владелец создаёт семью и шлёт CKShare-ссылку; остальные принимают после установки из TestFlight.

Builds в TestFlight живут 90 дней. Артефакты Xcode Cloud — 30 дней; для App Store-bound билдов скачать symbols.

#### Fallback: local Archive

Только если Xcode Cloud недоступен:

1. Увеличить `CURRENT_PROJECT_VERSION`.
2. Product → Archive (схема `App`, конфигурация **Release**).
3. Distribute App → App Store Connect → TestFlight.

### 4. Публичный App Store (опционально)

- Distribution → Manual release или автоматический.
- Privacy Nutrition Labels: имя, user ID, пользовательский контент (списки), геолокация магазинов — всё «App Functionality», без трекинга (`PrivacyInfo.xcprivacy` уже в проекте).
- Скриншоты iPhone 6.7" и 6.5" (можно с симулятора).
- Описание: «Семейный список покупок с синхронизацией через iCloud».
- Review notes: «Sign in with Apple required; family sharing via iCloud CKShare invite link in Settings».

### 5. Что не нужно для pet project

- Собственный сервер, Supabase, GitHub Actions, fastlane.
- Отдельная регистрация email/password.
- Несколько семейных пространств (код поддерживает, но UI скрывает создание второй группы).

### 6. Регулярная эксплуатация

- Следить за квотами CloudKit (для 4 человек — с запасом).
- При смене Core Data модели — снова deploy schema в Production.
- Xcode Cloud (или локальный Archive) для загрузки билдов в TestFlight.

## Безопасность: legacy Supabase

Файлы `SupabaseServices.swift`, `supabase/` и `invite-site/` удалены из текущего `main`. Publishable key из старого коммита `ebd4583` всё ещё виден в git history.

Обязательно:

1. В [Supabase Dashboard](https://supabase.com/dashboard) для проекта `<redacted>` — **rotate / revoke** publishable key и при возможности поставить проект на pause или удалить.
2. History rewrite (`git filter-repo` + force-push на `main`) намеренно не выполнялся автоматически: репозиторий private, но force-push на `main` требует явного ручного подтверждения владельца.

