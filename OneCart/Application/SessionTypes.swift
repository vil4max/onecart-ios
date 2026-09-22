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

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }

    var localizedTitleKey: LocalizedStringKey {
        switch self {
        case .system: "theme.system"
        case .light: "theme.light"
        case .dark: "theme.dark"
        }
    }

    var title: String {
        switch self {
        case .system: String(localized: "theme.system")
        case .light: String(localized: "theme.light")
        case .dark: String(localized: "theme.dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case ukrainian = "uk"
    case russian = "ru"

    var id: String {
        rawValue
    }

    var localizedTitleKey: LocalizedStringKey {
        switch self {
        case .system: "language.system"
        case .english: "language.english"
        case .ukrainian: "language.ukrainian"
        case .russian: "language.russian"
        }
    }

    var title: String {
        switch self {
        case .system: String(localized: "language.system")
        case .english: String(localized: "language.english")
        case .ukrainian: String(localized: "language.ukrainian")
        case .russian: String(localized: "language.russian")
        }
    }

    var languageCode: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .ukrainian: "uk"
        case .russian: "ru"
        }
    }

    var locale: Locale? {
        switch self {
        case .system: nil
        case .english: Locale(identifier: "en")
        case .ukrainian: Locale(identifier: "uk")
        case .russian: Locale(identifier: "ru")
        }
    }
}

@MainActor
@Observable
final class DevicePreferences {
    var onAccentChanged: ((AppAccentColor) -> Void)?
    var onThemeChanged: ((AppTheme) -> Void)?
    /// Fires after any preference is persisted; the session refreshes the widget snapshot from it.
    var onChanged: (() -> Void)?

    var theme: AppTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: Keys.theme)
            defaults.synchronize()
            OneCartAppGroup.defaults?.set(theme.rawValue, forKey: Keys.theme)
            onThemeChanged?(theme)
            onChanged?()
        }
    }

    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            if let code = language.languageCode {
                defaults.set([code], forKey: "AppleLanguages")
            } else {
                defaults.removeObject(forKey: "AppleLanguages")
            }
            defaults.synchronize()
            onChanged?()
        }
    }

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
        willSet {
            OneCartPalette.currentAccent = newValue
        }
        didSet {
            defaults.set(accentColor.rawValue, forKey: Keys.accentColor)
            defaults.synchronize()
            if defaults == .standard {
                OneCartAppGroup.defaults?.set(accentColor.rawValue, forKey: Keys.accentColor)
                OneCartAppGroup.defaults?.synchronize()
            }
            OneCartPalette.currentAccent = accentColor
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

    var effectiveLocale: Locale {
        language.locale ?? .autoupdatingCurrent
    }

    private let defaults: UserDefaults

    /// Theme and language follow the device (appearance, per-app language in iOS Settings) and
    /// the accent follows the app icon; values stored by older versions are dropped at launch.
    /// `didSet` does not run in `init`, so `AppleLanguages` keeps the system's per-app choice.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = .system
        defaults.removeObject(forKey: Keys.theme)
        if defaults == .standard {
            OneCartAppGroup.defaults?.set(AppTheme.system.rawValue, forKey: Keys.theme)
        }
        language = .system
        defaults.removeObject(forKey: Keys.language)
        let storedIcon = defaults.string(forKey: Keys.appIcon) ?? ""
        let initialIcon = AppIconOption(rawValue: storedIcon) ?? .classic
        appIcon = initialIcon
        let initialAccent = initialIcon.accent
        accentColor = initialAccent
        OneCartPalette.currentAccent = initialAccent
        defaults.set(initialAccent.rawValue, forKey: Keys.accentColor)
        if defaults == .standard {
            OneCartAppGroup.defaults?.set(initialAccent.rawValue, forKey: Keys.accentColor)
        }
        let stored = defaults.string(forKey: Keys.participantDisplayName) ?? ""
        participantDisplayName = ParticipantDisplayName.isPlaceholder(stored) ? "" : stored
    }

    func reloadFromDefaults() {
        if theme != .system {
            theme = .system
        }
        defaults.removeObject(forKey: Keys.theme)
        // Assigning `language` would rewrite `AppleLanguages`; it is always `.system` now.
        defaults.removeObject(forKey: Keys.language)
        let storedIcon = defaults.string(forKey: Keys.appIcon) ?? ""
        appIcon = AppIconOption(rawValue: storedIcon) ?? .classic
        accentColor = appIcon.accent
        OneCartPalette.currentAccent = accentColor
        let stored = defaults.string(forKey: Keys.participantDisplayName) ?? ""
        participantDisplayName = ParticipantDisplayName.isPlaceholder(stored) ? "" : stored
    }

    private enum Keys {
        static let theme = "onecart.theme"
        static let language = "onecart.language"
        static let accentColor = "onecart.accent-color"
        static let appIcon = "onecart.app-icon"
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

/// Why the welcome flow failed. Only `.storeLoad` may arm the explicit store wipe on Retry,
/// so the decision never depends on a localized message.
enum WelcomeFailureCause: Equatable {
    case storeLoad
    case other
}
