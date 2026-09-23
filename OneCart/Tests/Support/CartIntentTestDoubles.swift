import AuthenticationServices
import Foundation
@testable import OneCart

/// Holds startup at the credential check until the test releases it.
final class GatedAppleSignIn: AppleSignInAuthenticating, @unchecked Sendable {
    private let credential: AppleSignInCredential
    private let asked = AsyncStream<Void>.makeStream()
    private let gate = AsyncStream<Void>.makeStream()

    init(credential: AppleSignInCredential) {
        self.credential = credential
    }

    func storedCredential() -> AppleSignInCredential? {
        credential
    }

    func save(_: AppleSignInCredential) {}

    func clearCredential() {}

    func credentialState(for _: String) async -> AppleSignInCredentialState {
        asked.continuation.yield()
        for await _ in gate.stream {}
        return .authorized
    }

    func signIn() async throws -> AppleSignInCredential {
        throw AppleSignInError.failed
    }

    func makeCredential(from _: ASAuthorization) throws -> AppleSignInCredential {
        throw AppleSignInError.failed
    }

    func waitUntilAsked() async {
        var iterator = asked.stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func release() {
        gate.continuation.finish()
    }
}

/// A manual clock for `CartIntentDeadline`: time moves only when the test says so.
@MainActor
final class IntentTestClock {
    private let start = ContinuousClock.now
    private var elapsed: Duration = .zero
    private var sleepers: [(id: UUID, until: Duration, continuation: CheckedContinuation<Void, Never>)] = []

    func deadline(limit: Duration = CartIntentDeadline.startupLimit) -> CartIntentDeadline {
        CartIntentDeadline(
            end: start + limit,
            now: { self.start + self.elapsed },
            sleep: { duration in try await self.sleep(for: duration) }
        )
    }

    /// Moves time and fires every timer that is due.
    func advance(by duration: Duration) {
        elapsed += duration
        let due = sleepers.filter { $0.until <= elapsed }
        sleepers.removeAll { $0.until <= elapsed }
        due.forEach { $0.continuation.resume() }
    }

    /// Moves time without firing timers, as when work and the timer end in the same instant.
    func moveNowWithoutFiring(by duration: Duration) {
        elapsed += duration
    }

    /// Like `Task.sleep`, a cancelled sleep ends at once and throws.
    private func sleep(for duration: Duration) async throws {
        let id = UUID()
        let until = elapsed + duration
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                sleepers.append((id, until, continuation))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.wake(id) }
        }
        try Task.checkCancellation()
    }

    private func wake(_ id: UUID) {
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return }
        sleepers.remove(at: index).continuation.resume()
    }
}
