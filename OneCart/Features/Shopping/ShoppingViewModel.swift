import Combine

// RC05: Keeps Home-level shopping mutations at the feature boundary.
@MainActor
final class ShoppingViewModel: ObservableObject {
    private let session: AppSession

    init(session: AppSession) {
        self.session = session
    }

    func createFamilySpace(name: String) async {
        await session.createFamilySpace(name: name)
    }

    func refreshFamilyCartFromCloud() async {
        await session.refreshFamilyCartFromCloud()
    }
}
