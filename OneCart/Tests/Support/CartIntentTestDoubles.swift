import AuthenticationServices
import Foundation
@testable import OneCart

/// Resolves a dialog the way Siri does: late, in the language of the request.
func spoken(_ resource: LocalizedStringResource, in language: String = "en") -> String {
    var resource = resource
    resource.locale = Locale(identifier: language)
    return String(localized: resource)
}

/// "What's left" for `count` to-buy lines named A, B, C… plus one bought line.
func remainingSpeech(count: Int) -> LocalizedStringResource {
    let names = (0..<count).map { String(UnicodeScalar(UInt8(65 + $0))) }
    return CartIntentSpeech.remaining(CartIntentRemaining(totalCount: count + 1, names: names))
}

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
