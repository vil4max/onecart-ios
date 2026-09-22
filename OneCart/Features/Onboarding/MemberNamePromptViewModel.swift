import Foundation

/// Asks once for the name the family sees when Sign in with Apple gave none (REQ-AUTH-040).
@MainActor
@Observable
final class MemberNamePromptViewModel {
    var name = ""
    private(set) var isSaving = false
    private let prompting: any MemberNamePrompting

    init(prompting: any MemberNamePrompting) {
        self.prompting = prompting
    }

    var isPresented: Bool {
        prompting.shouldPromptForMemberName
    }

    var canSave: Bool {
        !isSaving && !ParticipantDisplayName.isPlaceholder(name)
    }

    func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        await prompting.saveMemberName(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func notNow() {
        guard prompting.shouldPromptForMemberName else { return }
        prompting.declineMemberNamePrompt()
    }

    /// A swipe-down closes the sheet without a choice; treat it as "Not now" so it never nags.
    func handleDismissal() {
        guard !isSaving else { return }
        notNow()
    }
}
