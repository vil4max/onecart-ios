import CoreData
import Foundation
@testable import OneCart
import Testing

/// The shared member profile that carries each member's chosen name to the others (REQ-AUTH-040).
@MainActor
@Suite("MemberProfileTests")
struct MemberProfileTests {
    private struct Row: Sendable, Equatable {
        let recordName: String?
        let name: String?
        let familyID: UUID?
        let scope: PersistentStoreScope?
        let updatedAt: Date?
        let isDeleted: Bool
    }

    private func rows(in fixture: MembershipSessionFixture) async throws -> [Row] {
        let persistence = fixture.persistence
        return try await persistence.performBackgroundTask { context in
            let request = MemberProfileEntity.fetchRequest()
            return try context.fetch(request).map { profile in
                Row(
                    recordName: profile.userRecordName,
                    name: profile.displayName,
                    familyID: profile.familySpace?.id,
                    scope: persistence.scope(for: profile),
                    updatedAt: profile.updatedAt,
                    isDeleted: profile.deletedAt != nil
                )
            }
        }
    }

    private func insertProfile(
        in fixture: MembershipSessionFixture,
        familyID: UUID,
        recordName: String,
        name: String,
        updatedAt: Date
    ) async throws {
        let persistence = fixture.persistence
        try await persistence.performBackgroundTask { context in
            let space = try FamilySpaceRepository.requireFamilySpace(id: familyID, in: context)
            let profile = MemberProfileEntity(context: context)
            try persistence.assign(profile, toSameStoreAs: space, in: context)
            profile.id = UUID()
            profile.userRecordName = recordName
            profile.displayName = name
            profile.createdAt = updatedAt
            profile.updatedAt = updatedAt
            profile.familySpace = space
        }
    }

    @Test("REQ-AUTH-040: a name change publishes one profile into the active cart, and repeats write nothing")
    func nameChangePublishesOneProfile() async throws {
        let fixture = try await MembershipSessionFixture.owner(
            displayName: "Alex",
            cloudUserIdentity: FakeCloudUserIdentity(recordName: "_alex")
        )
        let familyID = try #require(fixture.personalID)

        await fixture.session.updateParticipantDisplayName("  Мама ")

        let first = try await rows(in: fixture)
        #expect(first.count == 1)
        #expect(first.first?.recordName == "_alex")
        #expect(first.first?.name == "Мама")
        #expect(first.first?.familyID == familyID)
        #expect(first.first?.scope == .private)
        #expect(fixture.session.currentUserRecordName == "_alex")

        await fixture.session.updateParticipantDisplayName("Мама")
        await fixture.session.refreshFamilyMetadata(showErrors: false)
        #expect(try await rows(in: fixture) == first)

        await fixture.session.updateParticipantDisplayName("Mom")
        let renamed = try await rows(in: fixture)
        #expect(renamed.count == 1)
        #expect(renamed.first?.name == "Mom")
    }

    @Test("REQ-AUTH-040: a member publishes the profile into the shared cart's store")
    func memberPublishesIntoSharedStore() async throws {
        let fixture = try await MembershipSessionFixture.guest(
            displayName: "Sam",
            cloudUserIdentity: FakeCloudUserIdentity(recordName: "_sam")
        )
        let sharedID = try #require(fixture.sharedID)
        #expect(fixture.session.activeFamilySpace?.id == sharedID)

        await fixture.session.refreshFamilyMetadata(showErrors: false)

        let rows = try await rows(in: fixture)
        #expect(rows.count == 1)
        #expect(rows.first?.recordName == "_sam")
        #expect(rows.first?.name == "Sam")
        #expect(rows.first?.familyID == sharedID)
        #expect(rows.first?.scope == .shared)
    }

    @Test("REQ-AUTH-040: duplicate rows of one member resolve to the newest, and an upsert tombstones the rest")
    func duplicateRowsResolveToNewest() async throws {
        let fixture = try await MembershipSessionFixture.owner(displayName: "Alex")
        let familyID = try #require(fixture.personalID)
        let older = Date(timeIntervalSinceReferenceDate: 1000)
        let newer = Date(timeIntervalSinceReferenceDate: 2000)
        try await insertProfile(in: fixture, familyID: familyID, recordName: "_alex", name: "Old", updatedAt: newer)
        try await insertProfile(in: fixture, familyID: familyID, recordName: "_alex", name: "Older", updatedAt: older)
        try await insertProfile(in: fixture, familyID: familyID, recordName: "_bob", name: "Bob", updatedAt: older)

        let family = try #require(try fixture.repository.fetchFamilySpace(id: familyID))
        fixture.persistence.container.viewContext.refresh(family, mergeChanges: true)
        #expect(MemberProfileNames.latest(in: family) == ["_alex": "Old", "_bob": "Bob"])

        let wrote = try await fixture.repository.upsertMemberProfile(
            familySpaceID: familyID,
            userRecordName: "_alex",
            displayName: "Alex"
        )
        #expect(wrote)
        let living = try await rows(in: fixture).filter { !$0.isDeleted && $0.recordName == "_alex" }
        #expect(living.count == 1)
        #expect(living.first?.name == "Alex")

        let repeated = try await fixture.repository.upsertMemberProfile(
            familySpaceID: familyID,
            userRecordName: "_alex",
            displayName: "Alex"
        )
        #expect(!repeated)
    }

    @Test("REQ-AUTH-040: clearing the name withdraws it from the profile so members fall back")
    func clearingNameWithdrawsIt() async throws {
        let fixture = try await MembershipSessionFixture.owner(
            displayName: "Alex",
            cloudUserIdentity: FakeCloudUserIdentity(recordName: "_alex")
        )
        let familyID = try #require(fixture.personalID)
        await fixture.session.updateParticipantDisplayName("Мама")

        await fixture.session.updateParticipantDisplayName("   ")

        let rows = try await rows(in: fixture)
        #expect(rows.count == 1)
        #expect(rows.first?.name == nil)
        let family = try #require(try fixture.repository.fetchFamilySpace(id: familyID))
        fixture.persistence.container.viewContext.refresh(family, mergeChanges: true)
        #expect(MemberProfileNames.latest(in: family).isEmpty)
    }

    @Test("REQ-AUTH-040: without an iCloud identity nothing is published")
    func noIdentityPublishesNothing() async throws {
        let identity = FakeCloudUserIdentity(recordName: nil)
        let fixture = try await MembershipSessionFixture.owner(displayName: "Alex", cloudUserIdentity: identity)

        await fixture.session.updateParticipantDisplayName("Мама")

        #expect(identity.callCount >= 1)
        #expect(try await rows(in: fixture).isEmpty)
        #expect(fixture.session.currentUserRecordName == nil)
    }

    @Test("REQ-AUTH-040: a store written by the previous model opens with the member profile entity")
    func previousModelStoreMigrates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OneCartMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("OneCart-private.sqlite")
        let familyID = UUID()

        let previous = try Self.previousModel()
        let oldContainer = NSPersistentContainer(name: "OneCartPrevious", managedObjectModel: previous)
        oldContainer.persistentStoreDescriptions = [Self.description(for: storeURL)]
        try Self.loadStores(of: oldContainer)
        let oldContext = oldContainer.viewContext
        let entity = try #require(previous.entitiesByName["FamilySpace"])
        let space = NSManagedObject(entity: entity, insertInto: oldContext)
        space.setValue(familyID, forKey: "id")
        space.setValue("Weekend", forKey: "name")
        try oldContext.save()
        for store in oldContainer.persistentStoreCoordinator.persistentStores {
            try oldContainer.persistentStoreCoordinator.remove(store)
        }

        let current = OneCartManagedObjectModel.makeModel()
        let newContainer = NSPersistentContainer(name: "OneCartCurrent", managedObjectModel: current)
        newContainer.persistentStoreDescriptions = [Self.description(for: storeURL)]
        try Self.loadStores(of: newContainer)

        let request = NSFetchRequest<NSManagedObject>(entityName: "FamilySpace")
        let migrated = try newContainer.viewContext.fetch(request)
        #expect(migrated.count == 1)
        #expect(migrated.first?.value(forKey: "id") as? UUID == familyID)
        #expect(migrated.first?.value(forKey: "name") as? String == "Weekend")
        #expect(try newContainer.viewContext.count(for: NSFetchRequest(entityName: "MemberProfile")) == 0)
    }

    /// The shipped V7 model: today's model without `MemberProfile`, mapped to plain objects so
    /// the two models never claim the same classes.
    private static func previousModel() throws -> NSManagedObjectModel {
        let model = try #require(OneCartManagedObjectModel.makeModel().copy() as? NSManagedObjectModel)
        model.versionIdentifiers = ["OneCartCoreDataV7"]
        model.entities = model.entities.filter { $0.name != "MemberProfile" }
        for entity in model.entities {
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
            entity.properties = entity.properties.filter { $0.name != "memberProfiles" }
        }
        return model
    }

    private static func description(for url: URL) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        return description
    }

    private static func loadStores(of container: NSPersistentContainer) throws {
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }
    }
}
