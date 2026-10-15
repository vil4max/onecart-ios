import CoreData
import Foundation

/// Builds the focused Core Data repositories over one store, permission check and clock.
/// `AppSession` takes them from here and hands each collaborator only the protocol it needs.
///
/// Transitional: the forwarding methods below keep the earlier single-entry API for tests and
/// seeding helpers; production code calls the protocols, not these forwards.
final class FamilySpaceRepository: Sendable {
    let persistence: PersistenceController
    let families: CoreDataFamilyRepository
    let cartItems: CoreDataCartItemsRepository
    let purchaseArchiver: CoreDataPurchaseArchiver
    let deduplicator: CoreDataCartDeduplicator
    let personalCartRestorer: CoreDataPersonalCartRestorer
    let memberProfiles: CoreDataMemberProfileStore

    init(
        persistence: PersistenceController,
        permissionAuthorizer: PermissionAuthorizing,
        clock: AppClock = .live
    ) {
        self.persistence = persistence
        families = CoreDataFamilyRepository(
            persistence: persistence,
            permissionAuthorizer: permissionAuthorizer,
            clock: clock
        )
        cartItems = CoreDataCartItemsRepository(
            persistence: persistence,
            permissionAuthorizer: permissionAuthorizer,
            clock: clock
        )
        purchaseArchiver = CoreDataPurchaseArchiver(
            persistence: persistence,
            permissionAuthorizer: permissionAuthorizer,
            clock: clock
        )
        deduplicator = CoreDataCartDeduplicator(
            persistence: persistence,
            permissionAuthorizer: permissionAuthorizer,
            clock: clock
        )
        personalCartRestorer = CoreDataPersonalCartRestorer(
            persistence: persistence,
            permissionAuthorizer: permissionAuthorizer
        )
        memberProfiles = CoreDataMemberProfileStore(
            persistence: persistence,
            permissionAuthorizer: permissionAuthorizer,
            clock: clock
        )
    }

    // MARK: - Families

    @MainActor
    func fetchFamilySpaces(for userID: UUID? = nil) throws -> [FamilySpace] {
        try families.fetchFamilySpaces(for: userID)
    }

    @MainActor
    func fetchFamilySpace(id: UUID) throws -> FamilySpace? {
        try families.fetchFamilySpace(id: id)
    }

    func createFamilySpace(
        id: UUID = UUID(),
        name: String,
        createdAt: Date? = nil,
        cachedForUserID: UUID? = nil,
        isHouseholdDefault: Bool = false
    ) async throws -> UUID {
        try await families.createFamilySpace(
            id: id,
            name: name,
            createdAt: createdAt,
            cachedForUserID: cachedForUserID,
            isHouseholdDefault: isHouseholdDefault
        )
    }

    func claimUnassignedFamilySpaces(for userID: UUID) async throws {
        try await families.claimUnassignedFamilySpaces(for: userID)
    }

    func renameFamilySpace(id: UUID, name: String) async throws {
        try await families.renameFamilySpace(id: id, name: name)
    }

    func discardLocalSharedFamilySpace(id: UUID) async throws {
        try await families.discardLocalSharedFamilySpace(id: id)
    }

    // MARK: - Cart items

    @discardableResult
    func addProduct(
        to listID: UUID,
        id: UUID = UUID(),
        draft: ProductDraft,
        createdByName: String? = nil
    ) async throws -> UUID {
        try await cartItems.addProduct(to: listID, id: id, draft: draft, createdByName: createdByName)
    }

    func updateProduct(id: UUID, familySpaceID: UUID, draft: ProductDraft) async throws {
        try await cartItems.updateProduct(id: id, familySpaceID: familySpaceID, draft: draft)
    }

    func updateProductCategory(id: UUID, familySpaceID: UUID, category: ProductCategory) async throws {
        try await cartItems.updateProductCategory(id: id, familySpaceID: familySpaceID, category: category)
    }

    func setPurchasedState(
        id: UUID,
        familySpaceID: UUID,
        isPurchased: Bool,
        participantDisplayName: String?
    ) async throws {
        try await cartItems.setPurchasedState(
            id: id,
            familySpaceID: familySpaceID,
            isPurchased: isPurchased,
            participantDisplayName: participantDisplayName
        )
    }

    func setPurchased(
        id: UUID,
        familySpaceID: UUID,
        isPurchased: Bool,
        participantDisplayName: String?,
        purchasedAt: Date
    ) async throws {
        try await cartItems.setPurchased(
            id: id,
            familySpaceID: familySpaceID,
            isPurchased: isPurchased,
            participantDisplayName: participantDisplayName,
            purchasedAt: purchasedAt
        )
    }

    func deleteProduct(id: UUID, familySpaceID: UUID) async throws {
        try await cartItems.deleteProduct(id: id, familySpaceID: familySpaceID)
    }

    // MARK: - History, dedupe, restore, member profiles

    @discardableResult
    func completePurchased(listID: UUID) async throws -> UUID? {
        try await purchaseArchiver.completePurchased(listID: listID)
    }

    @discardableResult
    func archivePurchasedBefore(listID: UUID, cutoff: Date) async throws -> UUID? {
        try await purchaseArchiver.archivePurchasedBefore(listID: listID, cutoff: cutoff)
    }

    func deduplicateStableIDs() async throws {
        try await deduplicator.deduplicateStableIDs()
    }

    @discardableResult
    func deduplicateProductsByName() async throws -> Int {
        try await deduplicator.deduplicateProductsByName()
    }

    func restoreProvisionalPersonalContent(
        from sourceID: UUID,
        into destinationID: UUID,
        accountID: UUID
    ) async throws -> Bool {
        try await personalCartRestorer.restoreProvisionalPersonalContent(
            from: sourceID,
            into: destinationID,
            accountID: accountID
        )
    }

    @discardableResult
    func upsertMemberProfile(
        familySpaceID: UUID,
        userRecordName: String,
        displayName: String?,
        now: Date? = nil
    ) async throws -> Bool {
        try await memberProfiles.upsertMemberProfile(
            familySpaceID: familySpaceID,
            userRecordName: userRecordName,
            displayName: displayName,
            now: now
        )
    }

    // MARK: - Lookups on a caller's context

    static func fetchFamilySpace(id: UUID, in context: NSManagedObjectContext) throws -> FamilySpace? {
        try RepositoryFetch.familySpace(id: id, in: context)
    }

    static func requireFamilySpace(id: UUID, in context: NSManagedObjectContext) throws -> FamilySpace {
        try RepositoryFetch.requireFamilySpace(id: id, in: context)
    }

    static func fetchList(
        id: UUID,
        familySpaceID: UUID? = nil,
        in context: NSManagedObjectContext
    ) throws -> ShoppingListEntity? {
        try RepositoryFetch.list(id: id, familySpaceID: familySpaceID, in: context)
    }

    static func fetchProduct(
        id: UUID,
        familySpaceID: UUID? = nil,
        in context: NSManagedObjectContext
    ) throws -> ProductEntity? {
        try RepositoryFetch.product(id: id, familySpaceID: familySpaceID, in: context)
    }
}
