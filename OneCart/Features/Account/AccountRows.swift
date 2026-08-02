import SwiftUI

enum AccountActionStyle {
    case regular
    case destructive
}

struct AccountActionRow<Trailing: View>: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    var style: AccountActionStyle = .regular
    @ViewBuilder var trailing: () -> Trailing

    init(
        titleKey: LocalizedStringKey,
        systemImage: String,
        style: AccountActionStyle = .regular,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.style = style
        self.trailing = trailing
    }

    private var accent: Color {
        style == .destructive ? OneCartPalette.danger : OneCartPalette.primaryAccent
    }

    private var softFill: Color {
        style == .destructive
            ? OneCartPalette.danger.opacity(0.14)
            : OneCartPalette.primarySoft
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)
                .background(softFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(titleKey)
                .font(.body)
                .foregroundStyle(style == .destructive ? OneCartPalette.danger : .primary)

            Spacer(minLength: 0)

            trailing()
        }
        .contentShape(Rectangle())
    }
}

struct AccountMemberRow: View {
    let member: FamilyMember

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatarView(
                name: member.displayName,
                remoteURL: member.avatarURL,
                size: 44
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if member.isCurrentUser {
                        Text("common.you")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(OneCartPalette.primaryAccent)
                    }
                }
                Text(
                    member.access.isOwner
                        ? String(localized: "cart.owner_role")
                        : String(localized: "cart.member_role")
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
