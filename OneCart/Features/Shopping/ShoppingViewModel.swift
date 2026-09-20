import Combine

// RC05: Keeps Home-level shopping mutations at the feature boundary.
@MainActor
final class ShoppingViewModel: ObservableObject {
    private let session: AppSession

    init(session: AppSession) {
        self.session = session
    }

    func ensureHouseholdCartIfNeeded() async {
        await session.ensureHouseholdCartIfNeeded()
    }

    func retryHouseholdCartBootstrap() async {
        await session.retryHouseholdCartBootstrap()
    }
}

// MARK: - Cart celebration

/// Pure completion rules behind the confetti and the "all purchased" state,
/// kept out of the view so tests exercise the production conditions.
enum CartCelebration {
    static func isAllPurchased(totalCount: Int, toBuyCount: Int) -> Bool {
        totalCount > 0 && toBuyCount == 0
    }

    /// True when the toggle checks off the last remaining to-buy item.
    static func willCompleteCart(togglingPurchasedItem isPurchased: Bool, toBuyCount: Int) -> Bool {
        !isPurchased && toBuyCount == 1
    }
}
