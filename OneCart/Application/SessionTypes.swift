import Foundation
import SwiftUI

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

    @MainActor
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

    @MainActor
    static func displayOrPlaceholder(
        preferences: DevicePreferences,
        account: OneCartAccount?
    ) -> String {
        resolved(preferences: preferences, account: account) ?? placeholder
    }
}

@MainActor
@Observable
final class DevicePreferences {
    var onAccentChanged: ((AppAccentColor) -> Void)?
    /// Fires after any preference is persisted; the session refreshes the widget snapshot from it.
    var onChanged: (() -> Void)?

    var participantDisplayName: String {
        didSet {
            defaults.set(
                participantDisplayName.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: Keys.participantDisplayName
            )
            defaults.synchronize()
            onChanged?()
        }
    }

    var accentColor: AppAccentColor {
        didSet {
            defaults.set(accentColor.rawValue, forKey: Keys.accentColor)
            defaults.synchronize()
            appGroupDefaults?.set(accentColor.rawValue, forKey: Keys.accentColor)
            appGroupDefaults?.synchronize()
            onAccentChanged?(accentColor)
            onChanged?()
        }
    }

    var appIcon: AppIconOption {
        didSet {
            defaults.set(appIcon.rawValue, forKey: Keys.appIcon)
            defaults.synchronize()
            onChanged?()
        }
    }

    private let defaults: UserDefaults
    /// The App Group suite the widget reads the accent from; nil keeps every write in `defaults`
    /// (tests, the DEBUG demo).
    private let appGroupDefaults: UserDefaults?

    /// Appearance and language follow the device (per-app language in iOS Settings) and the
    /// accent follows the app icon. The app never writes `AppleLanguages`, so the system's
    /// per-app choice stays in place.
    init(defaults: UserDefaults, appGroupDefaults: UserDefaults?) {
        self.defaults = defaults
        self.appGroupDefaults = appGroupDefaults
        Self.removeRetiredKeys(from: defaults, appGroupDefaults: appGroupDefaults)
        let storedIcon = defaults.string(forKey: Keys.appIcon) ?? ""
        let initialIcon = AppIconOption(rawValue: storedIcon) ?? .classic
        appIcon = initialIcon
        let initialAccent = initialIcon.accent
        accentColor = initialAccent
        defaults.set(initialAccent.rawValue, forKey: Keys.accentColor)
        appGroupDefaults?.set(initialAccent.rawValue, forKey: Keys.accentColor)
        let stored = defaults.string(forKey: Keys.participantDisplayName) ?? ""
        participantDisplayName = ParticipantDisplayName.isPlaceholder(stored) ? "" : stored
    }

    func reloadFromDefaults() {
        Self.removeRetiredKeys(from: defaults, appGroupDefaults: appGroupDefaults)
        let storedIcon = defaults.string(forKey: Keys.appIcon) ?? ""
        appIcon = AppIconOption(rawValue: storedIcon) ?? .classic
        accentColor = appIcon.accent
        let stored = defaults.string(forKey: Keys.participantDisplayName) ?? ""
        participantDisplayName = ParticipantDisplayName.isPlaceholder(stored) ? "" : stored
    }

    /// Older versions stored a theme and an in-app language; drop them so old installs are
    /// cleaned, the App Group copy of the theme included.
    private static func removeRetiredKeys(from defaults: UserDefaults, appGroupDefaults: UserDefaults?) {
        defaults.removeObject(forKey: Keys.retiredTheme)
        defaults.removeObject(forKey: Keys.retiredLanguage)
        appGroupDefaults?.removeObject(forKey: Keys.retiredTheme)
    }

    private enum Keys {
        static let retiredTheme = "onecart.theme"
        static let retiredLanguage = "onecart.language"
        static let accentColor = OneCartAppGroup.accentColorKey
        static let appIcon = "onecart.app-icon"
        static let participantDisplayName = "onecart.participant-display-name"
    }
}

enum InviteLinkError: LocalizedError, Equatable {
    case noCart
    case offline

    var errorDescription: String? {
        switch self {
        case .noCart:
            String(localized: "sync.invite_no_cart")
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

/// Why the welcome flow failed. Only `.storeLoad` may arm the explicit store wipe on Retry,
/// so the decision never depends on a localized message.
enum WelcomeFailureCause: Equatable {
    case storeLoad
    case other
}
