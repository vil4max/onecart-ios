import CoreData
import Foundation
@testable import OneCart
import Synchronization
import Testing

/// One live family by stable ID, the way the session reads it.
func familySpaceRequest(id: UUID) -> NSFetchRequest<FamilySpace> {
    let request = FamilySpace.fetchRequest()
    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
        NSPredicate(format: "id == %@", id as NSUUID),
        NSPredicate(format: "deletedAt == nil"),
    ])
    request.fetchLimit = 1
    return request
}

func familyMember(
    named name: String,
    access: FamilyAccess = .member,
    isCurrentUser: Bool = false
) -> FamilyMember {
    FamilyMember(
        id: UUID(),
        displayName: name,
        access: access,
        joinedAt: Date(),
        isCurrentUser: isCurrentUser,
        avatarURL: nil,
        bannerURL: nil
    )
}

/// Counts calls of an injected closure, e.g. a system permission request a test must not make.
@MainActor
final class CallCounter {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

/// "In-memory" stores are SQLite files in a temporary directory; a suite that builds one
/// removes it when it is done so test runs do not accumulate store files.
func removeStoreFiles(of persistence: PersistenceController) {
    // A session can outlive its test by a few hops (an appear sync still deduplicating or
    // archiving). Its next background task must fail with a Swift error, not save into the
    // destroyed coordinator, which raises an Objective-C exception and crashes the next test.
    // The account-deletion gate is the store's existing "reject every repository call" switch.
    // `.removesStores` first finishes the session's tracked tasks; what remains is a background
    // save that passed the gate just before it closed and is still running while the stores are
    // destroyed. Closing that window needs the store to drain its in-flight saves, which is a
    // production change.
    persistence.loadLock.withLock { persistence.accountDeletionInProgress = true }
    // Deleting the folder under an open SQLite connection logs "disk I/O error"; the
    // coordinator closes and truncates each loaded store first.
    let coordinator = persistence.container.persistentStoreCoordinator
    coordinator.performAndWait {
        for store in coordinator.persistentStores {
            guard let url = store.url else { continue }
            try? coordinator.destroyPersistentStore(at: url, type: NSPersistentStore.StoreType(rawValue: store.type))
        }
    }
    try? FileManager.default.removeItem(at: persistence.storeDirectoryURL)
}

/// Removes the stores a Swift Testing test opened through a fixture once the test body has
/// returned, so the fixture and every session or view model built on it are released first.
/// A suite whose tests build `CartFixture` or `MembershipSessionFixture` declares `.removesStores`.
struct StoreCleanupTrait: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(
        for _: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        guard testCase != nil else {
            try await function()
            return
        }
        let registry = StoreCleanupRegistry()
        do {
            try await StoreCleanupRegistry.$current.withValue(registry) {
                try await function()
            }
        } catch {
            await registry.finishSessionWork()
            registry.removeAll()
            throw error
        }
        await registry.finishSessionWork()
        registry.removeAll()
    }
}

extension Trait where Self == StoreCleanupTrait {
    static var removesStores: Self { StoreCleanupTrait() }
}

final class StoreCleanupRegistry: Sendable {
    @TaskLocal static var current: StoreCleanupRegistry?

    private struct WeakSession: Sendable {
        weak var session: AppSession?
    }

    private final class Flag: Sendable {
        private let state = Mutex(false)

        var isSet: Bool {
            state.withLock { $0 }
        }

        func set() {
            state.withLock { $0 = true }
        }
    }

    private let stores = Mutex<[PersistenceController]>([])
    private let sessions = Mutex<[WeakSession]>([])

    /// Hands the store to the running test's cleanup; records an issue outside `.removesStores`.
    static func register(_ persistence: PersistenceController) {
        guard let current else {
            Issue.record("A fixture store needs the .removesStores trait on its suite")
            return
        }
        current.stores.withLock { $0.append(persistence) }
    }

    /// Lets the cleanup finish the session's tracked work before its stores go. Held weakly: a
    /// session whose tasks are done is released with its test as before.
    static func register(session: AppSession) {
        current?.sessions.withLock { $0.append(WeakSession(session: session)) }
    }

    /// Cancels and awaits the work a session tracks (startup, category refinements, the widget
    /// drain, the member profile publish, leave recovery), so none of it writes into stores that
    /// `removeAll` is about to destroy. Untracked hops remain, such as a sync a hosted view
    /// started on appear; `removeStoreFiles` closes the repository gate for those. The wait is
    /// bounded so a task that ignores cancellation cannot hang the run.
    @MainActor
    fileprivate func finishSessionWork() async {
        for session in sessions.withLock({ $0.compactMap(\.session) }) {
            let tasks =
                Array(session.categoryRefinementTasks.values)
                + [session.startupTask, session.memberProfileTask, session.leaveRecoveryTask].compactMap { $0 }
            let widgetDrain = session.widgetSync.widgetDrainTask
            guard !tasks.isEmpty || widgetDrain != nil else { continue }
            tasks.forEach { $0.cancel() }
            widgetDrain?.cancel()
            let finished = Flag()
            Task {
                for task in tasks {
                    await task.value
                }
                _ = await widgetDrain?.result
                finished.set()
            }
            for _ in 0..<200 {
                if finished.isSet { break }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
    }

    fileprivate func removeAll() {
        for persistence in stores.withLock({ $0 }) {
            removeStoreFiles(of: persistence)
        }
    }
}
