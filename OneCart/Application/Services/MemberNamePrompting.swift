import Foundation

/// The one-time request for a name when Sign in with Apple gave none (REQ-AUTH-040).
@MainActor
protocol MemberNamePrompting: AnyObject {
    /// True while the signed-in user has only a placeholder name and has not declined.
    var shouldPromptForMemberName: Bool { get }
    func saveMemberName(_ name: String) async
    /// Remembered on the device; the name stays editable in Settings.
    func declineMemberNamePrompt()
}
