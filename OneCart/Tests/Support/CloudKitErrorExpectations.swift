import Foundation
@testable import OneCart
import Testing

/// `OneCartCloudKitError` is not `Equatable` (one case carries a `CKAccountStatus`), so a
/// thrown case is matched by its enum description. Records an issue when nothing is thrown
/// or when a different error type surfaces.
@MainActor
func expectCloudKitError(
    _ expected: OneCartCloudKitError,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        Issue.record("expected \(expected) but nothing was thrown", sourceLocation: sourceLocation)
    } catch let error as OneCartCloudKitError {
        #expect(
            String(describing: error) == String(describing: expected),
            "expected \(expected), got \(error)",
            sourceLocation: sourceLocation
        )
    } catch {
        Issue.record("expected \(expected), got \(error)", sourceLocation: sourceLocation)
    }
}
