import CloudKit
import CoreData
import Foundation
@testable import OneCart
import Synchronization

/// A container stand-in for the share code. Every object resolves to a record in one fixed zone
/// and has no `CKShare`; the zone purge succeeds, fails, or is held until the test finishes it,
/// so a leave can outlive its timeout.
final class FakeCloudKitShareStore: CloudKitShareStoring {
    enum PurgeOutcome {
        case succeed
        case fail(Error)
        case hold
    }

    struct PurgeCall: Equatable {
        let zoneID: CKRecordZone.ID
        let scope: PersistentStoreScope
    }

    private struct State {
        var purgeOutcome: PurgeOutcome = .succeed
        var purgeCalls: [PurgeCall] = []
        var persistedScopes: [PersistentStoreScope] = []
        var heldPurge: CheckedContinuation<Void, Error>?
    }

    static let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: "_owner")

    private let state = Mutex(State())

    init(purgeOutcome: PurgeOutcome = .succeed) {
        state.withLock { $0.purgeOutcome = purgeOutcome }
    }

    var purgeCalls: [PurgeCall] {
        state.withLock { $0.purgeCalls }
    }

    var isHoldingPurge: Bool {
        state.withLock { $0.heldPurge != nil }
    }

    /// Lets a held purge finish, as the container's late callback would.
    func finishHeldPurge(throwing error: Error? = nil) {
        let held = state.withLock { state in
            defer { state.heldPurge = nil }
            return state.heldPurge
        }
        if let error {
            held?.resume(throwing: error)
        } else {
            held?.resume()
        }
    }

    func fetchShares(matching _: [NSManagedObjectID]) throws -> [NSManagedObjectID: CKShare] {
        [:]
    }

    func recordID(for _: NSManagedObjectID) -> CKRecord.ID? {
        CKRecord.ID(recordName: "family-root", zoneID: Self.zoneID)
    }

    func share(objectWith _: NSManagedObjectID) async throws -> CKShare {
        throw OneCartCloudKitError.stillSyncing
    }

    /// The scope of each share save, in call order.
    var persistedScopes: [PersistentStoreScope] {
        state.withLock { $0.persistedScopes }
    }

    func persistUpdatedShare(_ share: CKShare, in scope: PersistentStoreScope) async throws -> CKShare {
        state.withLock { $0.persistedScopes.append(scope) }
        return share
    }

    func purgeObjectsAndRecordsInZone(with zoneID: CKRecordZone.ID, in scope: PersistentStoreScope) async throws {
        let outcome = state.withLock { state in
            state.purgeCalls.append(PurgeCall(zoneID: zoneID, scope: scope))
            return state.purgeOutcome
        }
        switch outcome {
        case .succeed:
            return
        case let .fail(error):
            throw error
        case .hold:
            try await withCheckedThrowingContinuation { continuation in
                state.withLock { $0.heldPurge = continuation }
            }
        }
    }

    func accountStatus() async throws -> CKAccountStatus {
        .available
    }

    func userRecordID() async throws -> CKRecord.ID {
        CKRecord.ID(recordName: "_fake-user")
    }
}
