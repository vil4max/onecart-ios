import Combine
import Foundation

enum ParticipantDisplayName {
    static var placeholder: String {
        String(localized: "common.default_user")
    }

    static func isPlaceholder(_ raw: String?) -> Bool {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return true }
        let known: Set<String> = [
            placeholder,
            "User",
            "Пользователь",
            "Користувач",
            "Family member",
            "Участник семьи",
            "Учасник родини",
        ]
        return known.contains(trimmed)
    }

    static func resolved(
        preferences: DevicePreferences,
        account: OneCartAccount?
    ) -> String? {
        let preferred = preferences.participantDisplayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !isPlaceholder(preferred) {
            return preferred
        }
        let accountName = account?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !isPlaceholder(accountName) {
            return accountName
        }
        return nil
    }

    static func displayOrPlaceholder(
        preferences: DevicePreferences,
        account: OneCartAccount?
    ) -> String {
        resolved(preferences: preferences, account: account) ?? placeholder
    }
}

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
        let stored = defaults.string(forKey: Keys.participantDisplayName) ?? ""
        participantDisplayName = ParticipantDisplayName.isPlaceholder(stored) ? "" : stored
    }

    func reloadFromDefaults() {
        let stored = defaults.string(forKey: Keys.participantDisplayName) ?? ""
        participantDisplayName = ParticipantDisplayName.isPlaceholder(stored) ? "" : stored
    }

    private enum Keys {
        static let participantDisplayName = "onecart.participant-display-name"
    }
}

enum InviteLinkError: LocalizedError, Equatable {
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
