# ADR 0002: CloudKit как родной backend OneCart

Статус: принято, 2026-07-22.

## Контекст

OneCart используется как личное iOS-приложение и не нуждается в собственной публичной системе регистрации. Приоритеты — минимум внешней инфраструктуры, offline-first работа, системный iCloud и семейный доступ.

## Решение

- Использовать `NSPersistentCloudKitContainer` с private и shared stores.
- Локальная сессия — Sign in with Apple (Keychain). Синхронизация и шаринг — iCloud-аккаунт устройства (`CKContainer`); без email/password backend.
- Публиковать корневой `FamilySpace` через `CKShare`; связанные объекты остаются в том же persistent store.
- Оставить имя, аватар и баннер локальными настройками устройства.
- Удалить Supabase SDK, RPC/Realtime sync, Auth UI, Edge Functions и серверную проверку каталога.
- Единственный клиент — нативный SwiftUI target; React/Vite/Capacitor-прототип из репозитория удалён.

## Последствия

- Приложению требуются Apple Developer capabilities iCloud/CloudKit и Push Notifications.
- Полноценный sharing flow проверяется на физических устройствах с разными iCloud-аккаунтами.
- Старый локальный Core Data кэш может быть экспортирован в iCloud без смены SQLite-путей.
- Supabase Auth users нельзя преобразовать в iCloud users. Серверные данные переносятся отдельно, а участников приглашают заново через `CKShare`.
- Серверная catalog Edge Function отсутствует; store/catalog UI снят с текущего shell (данные `Store` в Core Data остаются для sync graph).

## Clarification (2026-07-25)

Sign in with Apple remains for local session. CloudKit iCloud identity drives sync. Apple Family is product positioning; sharing uses CKShare link-join (`publicPermission = .readWrite`), not Family Sharing membership APIs.

## Clarification (2026-07-26)

Dual identity is intentional and must stay explicit in UX:

| Concern | Source of truth |
|---------|-----------------|
| App session / Keychain / local profile key | Sign in with Apple `user` → stable UUID |
| Sync, CKShare, who receives the family cart | Device iCloud account (`CKContainer`) |

Welcome copy and iCloud-unavailable errors must say that SIWA alone is not enough. Private Core Data carts are filtered by the SIWA-derived account id; shared-store carts follow the iCloud participant.

## Clarification (2026-07-26) — stability before features

CloudKit sharing and dual identity are already complex enough. Product scope for the current train prefers a **cart-only shell** (one cart, name-only add, share from home) over Settings prefs / stores / catalog / multi-list surfaces that enlarge the sync graph and UI failure modes. Re-expand only after the two-device invite path is reliable — see [product.md](../product.md) § Priority.

See [architecture.md](../architecture.md), [product.md](../product.md), [release.md](../release.md).
