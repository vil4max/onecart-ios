import Foundation
@testable import OneCart

/// A manual clock: time moves only when the test says so, and sleepers wake only on `advance`.
/// `now()` is read from Core Data background contexts too, so the state sits behind a lock.
final class TestClock: @unchecked Sendable {
    private struct Sleeper {
        let id: UUID
        let until: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    let start: Date
    private let instantStart = ContinuousClock.now
    private let lock = NSLock()
    private var elapsed: Duration = .zero
    private var sleepers: [Sleeper] = []

    /// A fixed noon keeps day-boundary rules (the overnight History cutoff) away from midnight.
    init(start: Date = TestClock.fixedNoon) {
        self.start = start
    }

    static let fixedNoon: Date = {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = .current
        components.year = 2026
        components.month = 3
        components.day = 14
        components.hour = 12
        return components.date ?? Date(timeIntervalSinceReferenceDate: 0)
    }()

    var appClock: AppClock {
        AppClock(now: { self.now() }, sleep: { try await self.sleep(for: $0) })
    }

    func now() -> Date {
        lock.withLock { start.addingTimeInterval(Self.seconds(elapsed)) }
    }

    var pendingSleepers: Int {
        lock.withLock { sleepers.count }
    }

    /// Moves time and wakes every sleeper that is due, earliest first.
    func advance(by duration: Duration) {
        let due: [Sleeper] = lock.withLock {
            elapsed += duration
            let due = sleepers.filter { $0.until <= elapsed }.sorted { $0.until < $1.until }
            sleepers.removeAll { $0.until <= elapsed }
            return due
        }
        due.forEach { $0.continuation.resume() }
    }

    /// Moves time without waking sleepers, as when work and a timer end in the same instant.
    func moveNowWithoutFiring(by duration: Duration) {
        lock.withLock { elapsed += duration }
    }

    /// Yields until `count` tasks sleep on this clock, so an `advance` cannot run before the
    /// sleep it is meant to end. Yields only; it never waits on real time.
    @MainActor
    func waitForSleepers(_ count: Int = 1, maxYields: Int = 10_000) async -> Bool {
        for _ in 0..<maxYields where pendingSleepers < count {
            await Task.yield()
        }
        return pendingSleepers >= count
    }

    /// Waits for a sleeper, moves time, then yields until the woken work shows its effect.
    @MainActor
    func advanceWhenSleeping(by duration: Duration, thenYieldUntil condition: () -> Bool) async -> Bool {
        guard await waitForSleepers() else { return false }
        advance(by: duration)
        for _ in 0..<10_000 where !condition() {
            await Task.yield()
        }
        return condition()
    }

    /// A `CartIntentDeadline` on this clock's virtual time.
    @MainActor
    func deadline(limit: Duration = CartIntentDeadline.startupLimit) -> CartIntentDeadline {
        let base = instantStart
        return CartIntentDeadline(
            end: base + limit,
            now: { base + self.lock.withLock { self.elapsed } },
            sleep: { duration in try await self.sleep(for: duration) }
        )
    }

    /// Like `Task.sleep`, a cancelled sleep ends at once and throws.
    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        // A zero sleep returns at once, as Task.sleep does, instead of waiting for advance(by:).
        guard duration > .zero else { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let cancelled = lock.withLock {
                    if Task.isCancelled { return true }
                    sleepers.append(Sleeper(id: id, until: elapsed + duration, continuation: continuation))
                    return false
                }
                if cancelled {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let sleeper: Sleeper? = lock.withLock {
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return sleepers.remove(at: index)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}

extension AppClock {
    /// Every sleep ends at once (a cancelled one still throws); for tests that only need the
    /// work after a delay, not the delay itself.
    static let immediate = AppClock(
        now: { TestClock.fixedNoon },
        sleep: { _ in try Task.checkCancellation() }
    )
}
