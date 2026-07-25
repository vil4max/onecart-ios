import AuthenticationServices
import Combine

// RC05: Keeps onboarding actions at the feature boundary.
@MainActor
final class WelcomeViewModel: ObservableObject {
    private let session: AppSession

    init(session: AppSession) {
        self.session = session
    }

    func completeAppleSignIn(authorization: ASAuthorization) async {
        await session.completeAppleSignIn(authorization: authorization)
    }

    func completeHouseholdAudience(_ audience: HouseholdAudience) async {
        await session.completeHouseholdAudience(audience)
    }

    func retryWelcome() async {
        await session.retryWelcome()
    }

    func reportWelcomeFailure(_ message: String) {
        session.reportWelcomeFailure(message)
    }
}
