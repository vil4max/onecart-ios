import SwiftUI
import UIKit

/// Settings' way to reach support or report a problem, offensive content or a cart member
/// (REQ-SHELL-070). A tap offers the email or the address itself: an iPhone with no email
/// account still gets the address, and an email app that cannot open copies it instead.
struct SupportContactRow: View {
    let contact: SupportContact
    let appVersion: AppVersionInfo

    @Environment(\.openURL) private var openURL
    @State private var isChoosing = false
    @State private var copyReason: CopyReason?

    var body: some View {
        Button {
            isChoosing = true
        } label: {
            Label("settings.support_row", systemImage: "envelope")
        }
        .tint(.primary)
        .accessibilityHint(Text("settings.support_hint"))
        .accessibilityIdentifier("account.support")
        .confirmationDialog("settings.support_title", isPresented: $isChoosing, titleVisibility: .visible) {
            Button("settings.support_write_email") { writeEmail() }
            Button("settings.support_copy_address") { copyAddress(.requested) }
        } message: {
            Text("settings.support_message")
        }
        .alert(copyReason?.titleKey ?? "", isPresented: isShowingCopyNotice) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("settings.support_copied_message \(contact.emailAddress)")
        }
    }

    private var isShowingCopyNotice: Binding<Bool> {
        Binding(
            get: { copyReason != nil },
            set: { isShowing in
                if !isShowing { copyReason = nil }
            }
        )
    }

    private func writeEmail() {
        let body = SupportContact.mailBody(appName: String(localized: "common.app_name"), appVersion: appVersion)
        guard let url = contact.mailURL(subject: String(localized: "settings.support_mail_subject"), body: body)
        else {
            copyAddress(.noEmailApp)
            return
        }
        openURL(url) { accepted in
            if !accepted { copyAddress(.noEmailApp) }
        }
    }

    private func copyAddress(_ reason: CopyReason) {
        UIPasteboard.general.string = contact.emailAddress
        copyReason = reason
    }
}

extension SupportContactRow {
    /// Why the address went to the clipboard; the notice says which.
    enum CopyReason {
        case requested
        case noEmailApp

        var titleKey: LocalizedStringKey {
            switch self {
            case .requested: "settings.support_copied_title"
            case .noEmailApp: "settings.support_no_mail_title"
            }
        }
    }
}
