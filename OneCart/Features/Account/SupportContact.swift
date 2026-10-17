import Foundation

/// Where people reach the developer from Settings: questions, problems, and reports of
/// offensive content or a cart member (REQ-SHELL-070).
struct SupportContact: Equatable, Sendable {
    /// The contact already published in the privacy policy (`docs/privacy.md`); change both together.
    static let published = SupportContact(emailAddress: "vil4max@gmail.com")

    let emailAddress: String

    /// Only RFC 3986 unreserved characters stay literal. `URLComponents` would keep `&`, `=` and
    /// `+` in query values, which split or alter a translated subject in some mail apps.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// The prefilled body: room to write first, then the app's name, version and build, so a
    /// report names the build it came from.
    static func mailBody(appName: String, appVersion: AppVersionInfo) -> String {
        "\n\n\n—\n\(appName) \(appVersion.version) (\(appVersion.build))"
    }

    func mailURL(subject: String, body: String) -> URL? {
        guard let subject = subject.addingPercentEncoding(withAllowedCharacters: Self.unreserved),
            let body = body.addingPercentEncoding(withAllowedCharacters: Self.unreserved)
        else { return nil }
        return URL(string: "mailto:\(emailAddress)?subject=\(subject)&body=\(body)")
    }
}
