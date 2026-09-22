import Foundation
@testable import OneCart

@MainActor
@Observable
final class FakeHouseholdCartBootstrapper: HouseholdCartBootstrapping {
    var householdCartBootstrapFailed = false
    var ensureCount = 0
    var retryCount = 0

    func ensureHouseholdCartIfNeeded() async {
        ensureCount += 1
    }

    func retryHouseholdCartBootstrap() async {
        retryCount += 1
    }
}
