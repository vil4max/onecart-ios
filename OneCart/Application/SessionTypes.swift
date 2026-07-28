import Combine
import Foundation

typealias AppModel = AppSession

final class DevicePreferences: ObservableObject {
    @Published var participantDisplayName: String {
        didSet {
            defaults.set(
                participantDisplayName.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: Keys.participantDisplayName
            )
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        participantDisplayName = defaults.string(
            forKey: Keys.participantDisplayName
        ) ?? ""
    }

    func reloadFromDefaults() {
        participantDisplayName = defaults.string(
            forKey: Keys.participantDisplayName
        ) ?? ""
    }

    private enum Keys {
        static let participantDisplayName = "onecart.participant-display-name"
    }
}

enum InviteLinkError: LocalizedError {
    case notOwner
    case offline

    var errorDescription: String? {
        switch self {
        case .notOwner:
            String(localized: "sync.invite_owner_only")
        case .offline:
            String(localized: "sync.invite_need_network")
        }
    }
}

enum WelcomePhase: Equatable {
    case signIn
    case connecting
    case failed(String)
}
