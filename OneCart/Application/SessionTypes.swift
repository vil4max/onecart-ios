import Combine
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

final class DevicePreferences: ObservableObject {
    var onAccentChanged: ((AppAccentColor) -> Void)?
    var onThemeChanged: ((AppTheme) -> Void)?

    @Published var theme: AppTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: Keys.theme)
            defaults.synchronize()
            OneCartAppGroup.defaults?.set(theme.rawValue, forKey: Keys.theme)
            onThemeChanged?(theme)
        }
    }

    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            if let code = language.languageCode {
                defaults.set([code], forKey: "AppleLanguages")
            } else {
                defaults.removeObject(forKey: "AppleLanguages")
            }
            defaults.synchronize()
        }
    }

    @Published var participantDisplayName: String {
        didSet {
            defaults.set(
                participantDisplayName.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: Keys.participantDisplayName
            )
            defaults.synchronize()
        }
    }

    @Published var accentColor: AppAccentColor {
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
        }
    }

    @Published var appIcon: AppIconOption {
        didSet {
            defaults.set(appIcon.rawValue, forKey: Keys.appIcon)
            defaults.synchronize()
        }
    }

    var effectiveLocale: Locale {
        language.locale ?? .autoupdatingCurrent
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedTheme = defaults.string(forKey: Keys.theme) ?? ""
        let initialTheme = AppTheme(rawValue: storedTheme) ?? .system
        theme = initialTheme
        if defaults == .standard {
            OneCartAppGroup.defaults?.set(initialTheme.rawValue, forKey: Keys.theme)
        }
        let storedLanguage = defaults.string(forKey: Keys.language) ?? ""
        language = AppLanguage(rawValue: storedLanguage) ?? .system
        let storedAccent = defaults.string(forKey: Keys.accentColor)
            ?? (defaults == .standard ? OneCartAppGroup.defaults?.string(forKey: Keys.accentColor) : nil)
            ?? ""
        let initialAccent = AppAccentColor(rawValue: storedAccent) ?? .emerald
        accentColor = initialAccent
        OneCartPalette.currentAccent = initialAccent
        if defaults == .standard {
            OneCartAppGroup.defaults?.set(initialAccent.rawValue, forKey: Keys.accentColor)
        }
        let storedIcon = defaults.string(forKey: Keys.appIcon) ?? ""
        appIcon = AppIconOption(rawValue: storedIcon) ?? .classic
        let stored = defaults.string(forKey: Keys.participantDisplayName) ?? ""
        participantDisplayName = ParticipantDisplayName.isPlaceholder(stored) ? "" : stored
    }

    func reloadFromDefaults() {
        let storedTheme = defaults.string(forKey: Keys.theme) ?? ""
        let reloadedTheme = AppTheme(rawValue: storedTheme) ?? .system
        theme = reloadedTheme
        if defaults == .standard {
            OneCartAppGroup.defaults?.set(reloadedTheme.rawValue, forKey: Keys.theme)
        }
        let storedLanguage = defaults.string(forKey: Keys.language) ?? ""
        language = AppLanguage(rawValue: storedLanguage) ?? .system
        let storedAccent = defaults.string(forKey: Keys.accentColor)
            ?? (defaults == .standard ? OneCartAppGroup.defaults?.string(forKey: Keys.accentColor) : nil)
            ?? ""
        let reloadedAccent = AppAccentColor(rawValue: storedAccent) ?? .emerald
        accentColor = reloadedAccent
        OneCartPalette.currentAccent = reloadedAccent
        if defaults == .standard {
            OneCartAppGroup.defaults?.set(reloadedAccent.rawValue, forKey: Keys.accentColor)
        }
        let storedIcon = defaults.string(forKey: Keys.appIcon) ?? ""
        appIcon = AppIconOption(rawValue: storedIcon) ?? .classic
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
