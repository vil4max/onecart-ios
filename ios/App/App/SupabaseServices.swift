import Foundation
import Supabase

enum OneCartSupabaseConfiguration {
    static let url = URL(string: "https://<redacted>.supabase.co")!
    static let publishableKey = "<redacted>"
    static let inviteFunctionURL = url
        .appendingPathComponent("functions")
        .appendingPathComponent("v1")
        .appendingPathComponent("onecart-invite")
}

struct OneCartAccount: Equatable {
    let id: UUID
    let displayName: String
    let email: String
}

enum RegistrationResult: Equatable {
    case signedIn(OneCartAccount)
    case confirmationRequired(email: String)
}

enum FamilyAccess: String, Equatable {
    case owner
    case member

    var title: String {
        switch self {
        case .owner: return "Владелец семьи"
        case .member: return "Участник семьи"
        }
    }

    var canEdit: Bool { true }
    var isOwner: Bool { self == .owner }
    var isParticipant: Bool { self == .member }
}

enum OneCartSyncState: Equatable {
    case synchronized
    case syncing
    case offline
    case failed

    var title: String {
        switch self {
        case .synchronized: return "Синхронизировано"
        case .syncing: return "Синхронизация…"
        case .offline: return "Офлайн — изменения сохранены"
        case .failed: return "Синхронизация приостановлена"
        }
    }

    var systemImage: String {
        switch self {
        case .synchronized: return "checkmark.circle.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .offline: return "wifi.slash"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}

struct FamilyMember: Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let email: String?
    let access: FamilyAccess
    let joinedAt: Date
    let isCurrentUser: Bool
}

struct FamilyInvitation: Identifiable, Equatable {
    let id: UUID
    let familyID: UUID
    let familyName: String
    let invitedByName: String
    let email: String
    let expiresAt: Date
    let createdAt: Date
}

struct FamilyInviteLink: Identifiable, Equatable {
    let token: UUID
    let familyName: String
    let expiresAt: Date

    var id: UUID { token }
    var url: URL { OneCartInviteURL.shareURL(for: token) }

    var shareMessage: String {
        "Присоединяйтесь к семье «\(familyName)» в OneCart\n\n\(url.absoluteString)"
    }
}

struct FamilyInvitePreview: Identifiable, Equatable {
    let token: UUID
    let familyID: UUID
    let familyName: String
    let memberCount: Int
    let expiresAt: Date

    var id: UUID { token }
}

enum OneCartInviteURL {
    static func shareURL(for token: UUID) -> URL {
        var components = URLComponents(
            url: OneCartSupabaseConfiguration.inviteFunctionURL,
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "token", value: token.uuidString.lowercased()),
        ]
        return components.url!
    }

    static func token(from url: URL) -> UUID? {
        let scheme = url.scheme?.lowercased()
        if scheme == "onecart" {
            var route = url.pathComponents
                .filter { $0 != "/" }
                .map { $0.lowercased() }
            if let host = url.host?.lowercased() {
                route.insert(host, at: 0)
            }
            guard route.count == 2, route[0] == "invite" else { return nil }
            return UUID(uuidString: route[1])
        }

        guard scheme == "https",
              url.host?.lowercased() == OneCartSupabaseConfiguration.url.host?.lowercased(),
              url.path == "/functions/v1/onecart-invite",
              let tokenValue = URLComponents(
                  url: url,
                  resolvingAgainstBaseURL: false
              )?.queryItems?.first(where: { $0.name == "token" })?.value
        else {
            return nil
        }
        return UUID(uuidString: tokenValue)
    }
}

private enum OneCartBackendError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        "Сервер вернул неполный ответ. Попробуйте ещё раз."
    }
}

struct RemoteFamilySummary: Codable, Equatable {
    let id: UUID
    let name: String
    let ownerID: UUID
    let role: String
    let createdAt: Date
    let updatedAt: Date

    var access: FamilyAccess {
        FamilyAccess(rawValue: role) ?? .member
    }

    enum CodingKeys: String, CodingKey {
        case id, name, role
        case ownerID = "owner_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct RemoteFamily: Codable, Equatable {
    let id: UUID
    let name: String
    let ownerID: UUID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case ownerID = "owner_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteStore: Codable, Equatable {
    let id: UUID
    let familyID: UUID?
    let name: String
    let icon: String
    let colorHex: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let externalAppURL: String?
    let isPinned: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, icon, address, latitude, longitude
        case familyID = "family_id"
        case colorHex = "color_hex"
        case externalAppURL = "external_app_url"
        case isPinned = "is_pinned"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteShoppingList: Codable, Equatable {
    let id: UUID
    let familyID: UUID?
    let storeID: UUID?
    let title: String
    let status: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, status
        case familyID = "family_id"
        case storeID = "store_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteProduct: Codable, Equatable {
    let id: UUID
    let familyID: UUID?
    let listID: UUID
    let storeID: UUID?
    let name: String
    let quantity: Double
    let unit: String
    let category: String
    let estimatedPrice: Double
    let originalPrice: Double?
    let imageURL: String?
    let sourceURL: String?
    let note: String
    let isPurchased: Bool
    let purchasedAt: Date?
    let purchasedByName: String?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, quantity, unit, category, note
        case familyID = "family_id"
        case listID = "list_id"
        case storeID = "store_id"
        case estimatedPrice = "estimated_price"
        case originalPrice = "original_price"
        case imageURL = "image_url"
        case sourceURL = "source_url"
        case isPurchased = "is_purchased"
        case purchasedAt = "purchased_at"
        case purchasedByName = "purchased_by_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemotePurchaseHistory: Codable, Equatable {
    let id: UUID
    let familyID: UUID?
    let storeID: UUID?
    let total: Double
    let purchasedAt: Date
    let memberNames: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, total
        case familyID = "family_id"
        case storeID = "store_id"
        case purchasedAt = "purchased_at"
        case memberNames = "member_names"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteHistoryItem: Codable, Equatable {
    let id: UUID
    let familyID: UUID?
    let historyID: UUID
    let name: String
    let quantity: Double
    let unit: String
    let category: String
    let estimatedPrice: Double
    let note: String
    let purchasedAt: Date?
    let purchasedByName: String?
    let storeName: String?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, quantity, unit, category, note
        case familyID = "family_id"
        case historyID = "history_id"
        case estimatedPrice = "estimated_price"
        case purchasedAt = "purchased_at"
        case purchasedByName = "purchased_by_name"
        case storeName = "store_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct FamilySnapshot: Codable, Equatable {
    let family: RemoteFamily?
    let stores: [RemoteStore]
    let shoppingLists: [RemoteShoppingList]
    let products: [RemoteProduct]
    let purchaseHistory: [RemotePurchaseHistory]
    let historyItems: [RemoteHistoryItem]

    enum CodingKeys: String, CodingKey {
        case family, stores, products
        case shoppingLists = "shopping_lists"
        case purchaseHistory = "purchase_history"
        case historyItems = "history_items"
    }
}

private struct RemoteFamilyMember: Codable {
    let userID: UUID
    let displayName: String
    let email: String?
    let role: String
    let joinedAt: Date
    let isCurrentUser: Bool

    enum CodingKeys: String, CodingKey {
        case email, role
        case userID = "user_id"
        case displayName = "display_name"
        case joinedAt = "joined_at"
        case isCurrentUser = "is_current_user"
    }
}

private struct RemoteInvitation: Codable {
    let id: UUID
    let familyID: UUID
    let familyName: String
    let invitedByName: String
    let email: String
    let expiresAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, email
        case familyID = "family_id"
        case familyName = "family_name"
        case invitedByName = "invited_by_name"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

private struct RemoteFamilyInviteLink: Codable {
    let inviteToken: UUID
    let expiresAt: Date
    let familyName: String

    enum CodingKeys: String, CodingKey {
        case inviteToken = "invite_token"
        case expiresAt = "expires_at"
        case familyName = "family_name"
    }
}

private struct RemoteFamilyInvitePreview: Codable {
    let familyID: UUID
    let familyName: String
    let memberCount: Int
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case familyID = "family_id"
        case familyName = "family_name"
        case memberCount = "member_count"
        case expiresAt = "expires_at"
    }
}

@MainActor
final class SupabaseBackendService {
    let client: SupabaseClient
    private var realtimeChannel: RealtimeChannelV2?

    init(client: SupabaseClient? = nil) {
        self.client = client ?? SupabaseClient(
            supabaseURL: OneCartSupabaseConfiguration.url,
            supabaseKey: OneCartSupabaseConfiguration.publishableKey
        )
    }

    var cachedAccount: OneCartAccount? {
        client.auth.currentUser.map(Self.account(from:))
    }

    func restoredAccount() async -> OneCartAccount? {
        guard let cachedAccount else { return nil }
        do {
            let session = try await client.auth.session
            return Self.account(from: session.user)
        } catch {
            // The Keychain session still identifies the local cache while offline.
            return cachedAccount
        }
    }

    func signIn(email: String, password: String) async throws -> OneCartAccount {
        let session = try await client.auth.signIn(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            password: password
        )
        return Self.account(from: session.user)
    }

    func register(
        displayName: String,
        email: String,
        password: String
    ) async throws -> RegistrationResult {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let response = try await client.auth.signUp(
            email: normalizedEmail,
            password: password,
            data: ["display_name": .string(normalizedName)]
        )
        if let session = response.session {
            return .signedIn(Self.account(from: session.user))
        }
        return .confirmationRequired(email: response.user.email ?? normalizedEmail)
    }

    func signOut() async throws {
        await stopRealtime()
        try await client.auth.signOut(scope: .local)
    }

    func families() async throws -> [RemoteFamilySummary] {
        try await client
            .rpc("get_my_families")
            .execute()
            .value
    }

    func familyMembers(familyID: UUID) async throws -> [FamilyMember] {
        let rows: [RemoteFamilyMember] = try await client
            .rpc("get_family_members", params: FamilyIDParameters(familyID: familyID))
            .execute()
            .value
        return rows.map {
            FamilyMember(
                id: $0.userID,
                displayName: $0.displayName,
                email: $0.email,
                access: FamilyAccess(rawValue: $0.role) ?? .member,
                joinedAt: $0.joinedAt,
                isCurrentUser: $0.isCurrentUser
            )
        }
    }

    func pendingInvitations() async throws -> [FamilyInvitation] {
        let rows: [RemoteInvitation] = try await client
            .rpc("get_pending_invitations")
            .execute()
            .value
        return rows.map {
            FamilyInvitation(
                id: $0.id,
                familyID: $0.familyID,
                familyName: $0.familyName,
                invitedByName: $0.invitedByName,
                email: $0.email,
                expiresAt: $0.expiresAt,
                createdAt: $0.createdAt
            )
        }
    }

    func createFamilyInviteLink(familyID: UUID) async throws -> FamilyInviteLink {
        let rows: [RemoteFamilyInviteLink] = try await client
            .rpc(
                "create_family_invite_link",
                params: FamilyIDParameters(familyID: familyID)
            )
            .execute()
            .value
        guard let row = rows.first else {
            throw OneCartBackendError.invalidResponse
        }
        return FamilyInviteLink(
            token: row.inviteToken,
            familyName: row.familyName,
            expiresAt: row.expiresAt
        )
    }

    func familyInvitePreview(token: UUID) async throws -> FamilyInvitePreview? {
        let rows: [RemoteFamilyInvitePreview] = try await client
            .rpc(
                "get_family_invite_preview",
                params: InviteTokenParameters(token: token)
            )
            .execute()
            .value
        guard let row = rows.first else { return nil }
        return FamilyInvitePreview(
            token: token,
            familyID: row.familyID,
            familyName: row.familyName,
            memberCount: row.memberCount,
            expiresAt: row.expiresAt
        )
    }

    func acceptFamilyInviteLink(token: UUID) async throws -> UUID {
        try await client
            .rpc(
                "accept_family_invite_link",
                params: InviteTokenParameters(token: token)
            )
            .execute()
            .value
    }

    func ensureFamily(
        id: UUID,
        name: String,
        createdAt: Date,
        updatedAt: Date
    ) async throws {
        try await client.rpc(
            "ensure_family",
            params: EnsureFamilyParameters(
                id: id,
                name: name,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        ).execute()
    }

    func snapshot(familyID: UUID) async throws -> FamilySnapshot {
        try await client
            .rpc("get_family_snapshot", params: FamilyIDParameters(familyID: familyID))
            .execute()
            .value
    }

    func synchronize(
        familyID: UUID,
        snapshot: FamilySnapshot
    ) async throws -> FamilySnapshot {
        try await client
            .rpc(
                "sync_family_snapshot",
                params: SyncSnapshotParameters(familyID: familyID, snapshot: snapshot)
            )
            .execute()
            .value
    }

    func invite(familyID: UUID, email: String) async throws {
        try await client.rpc(
            "create_family_invitation",
            params: InvitationParameters(
                familyID: familyID,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            )
        ).execute()
    }

    func acceptInvitation(id: UUID) async throws {
        try await client.rpc(
            "accept_family_invitation",
            params: InvitationIDParameters(invitationID: id)
        ).execute()
    }

    func leaveFamily(id: UUID) async throws {
        try await client.rpc(
            "leave_family",
            params: FamilyIDParameters(familyID: id)
        ).execute()
    }

    func removeMember(familyID: UUID, userID: UUID) async throws {
        try await client.rpc(
            "remove_family_member",
            params: RemoveMemberParameters(familyID: familyID, userID: userID)
        ).execute()
    }

    func listenForDatabaseChanges(onChange: @escaping @Sendable () -> Void) async throws {
        await stopRealtime()
        let channel = client.channel("onecart-\(UUID().uuidString)")
        realtimeChannel = channel

        // Subscribe only to shopping/family tables — never the whole `public` schema.
        // A schema-wide listener re-triggers sync on every RPC write echo and starves the UI.
        let tables = [
            "families",
            "family_members",
            "family_invitations",
            "stores",
            "shopping_lists",
            "products",
            "purchase_history",
            "history_items",
        ]
        let streams = tables.map { table in
            channel.postgresChange(AnyAction.self, schema: "public", table: table)
        }

        try await channel.subscribeWithError()

        await withTaskGroup(of: Void.self) { group in
            for stream in streams {
                group.addTask {
                    for await _ in stream {
                        guard !Task.isCancelled else { break }
                        onChange()
                    }
                }
            }
            await group.waitForAll()
        }

        await client.removeChannel(channel)
        if realtimeChannel === channel {
            realtimeChannel = nil
        }
    }

    func stopRealtime() async {
        if let realtimeChannel {
            await client.removeChannel(realtimeChannel)
            self.realtimeChannel = nil
        }
    }

    private static func account(from user: User) -> OneCartAccount {
        let email = user.email ?? ""
        let metadataName = user.userMetadata["display_name"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = email.split(separator: "@").first.map(String.init) ?? "Пользователь"
        return OneCartAccount(
            id: user.id,
            displayName: metadataName?.isEmpty == false ? metadataName! : fallbackName,
            email: email
        )
    }
}

private struct FamilyIDParameters: Encodable {
    let familyID: UUID

    enum CodingKeys: String, CodingKey {
        case familyID = "p_family_id"
    }
}

private struct EnsureFamilyParameters: Encodable {
    let id: UUID
    let name: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case name = "p_name"
        case createdAt = "p_created_at"
        case updatedAt = "p_updated_at"
    }
}

private struct SyncSnapshotParameters: Encodable {
    let familyID: UUID
    let snapshot: FamilySnapshot

    enum CodingKeys: String, CodingKey {
        case familyID = "p_family_id"
        case snapshot = "p_snapshot"
    }
}

private struct InvitationParameters: Encodable {
    let familyID: UUID
    let email: String

    enum CodingKeys: String, CodingKey {
        case familyID = "p_family_id"
        case email = "p_email"
    }
}

private struct InvitationIDParameters: Encodable {
    let invitationID: UUID

    enum CodingKeys: String, CodingKey {
        case invitationID = "p_invitation_id"
    }
}

private struct InviteTokenParameters: Encodable {
    let token: UUID

    enum CodingKeys: String, CodingKey {
        case token = "p_token"
    }
}

private struct RemoveMemberParameters: Encodable {
    let familyID: UUID
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case familyID = "p_family_id"
        case userID = "p_user_id"
    }
}
