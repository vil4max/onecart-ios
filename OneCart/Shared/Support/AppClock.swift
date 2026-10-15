import Foundation

/// Wall-clock time and sleeping for production logic. Types take it through their initializer so
/// tests drive time themselves instead of waiting it out; only `live` reads the real clock.
struct AppClock: Sendable {
    let now: @Sendable () -> Date
    /// Throws `CancellationError` when the sleeping task is cancelled, like `Task.sleep`.
    let sleep: @Sendable (Duration) async throws -> Void

    /// Sleeps on the suspending clock, which pauses while the device sleeps, matching the
    /// `Task.sleep(nanoseconds:)` timers it replaced (the 48 s watchdog stays above the 45 s
    /// invite ceiling even across a locked phone).
    static let live = AppClock(
        now: { Date() },
        sleep: { try await Task.sleep(for: $0, clock: .suspending) }
    )
}

extension AppClock {
    func sleep(nanoseconds: UInt64) async throws {
        try await sleep(.nanoseconds(Int64(clamping: nanoseconds)))
    }
}
