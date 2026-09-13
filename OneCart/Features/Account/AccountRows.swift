import SwiftUI

enum AccountActionStyle {
    case regular
    case destructive
}

struct AccountActionRow<Trailing: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let titleKey: LocalizedStringKey
    let systemImage: String
    var style: AccountActionStyle = .regular
    var accentColor: AppAccentColor?
    @ViewBuilder var trailing: () -> Trailing

    init(
        titleKey: LocalizedStringKey,
        systemImage: String,
        style: AccountActionStyle = .regular,
        accentColor: AppAccentColor? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.style = style
        self.accentColor = accentColor
        self.trailing = trailing
    }

    private var accent: Color {
        style == .destructive
            ? OneCartPalette.danger
            : OneCartPalette.primaryAccent(for: colorScheme, accent: accentColor)
    }

    private var softFill: Color {
        style == .destructive
            ? OneCartPalette.danger.opacity(0.14)
            : OneCartPalette.primarySoft(for: colorScheme, accent: accentColor)
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
        .animation(.easeInOut(duration: 0.35), value: accentColor)
    }
}

struct AccountMemberRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let member: FamilyMember
    var accent: AppAccentColor?

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatarView(
                name: member.displayName,
                remoteURL: member.avatarURL,
                size: 44,
                accent: accent
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if member.isCurrentUser {
                        Text("common.you")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(OneCartPalette.primaryAccent(for: colorScheme, accent: accent))
                    }
                }
                Text(
                    member.access.isOwner
                        ? "cart.owner_role"
                        : "cart.member_role"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .animation(.easeInOut(duration: 0.35), value: accent)
    }
}

struct AccountPickerRow<SelectionValue: Hashable, Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let titleKey: LocalizedStringKey
    let systemImage: String
    var accent: AppAccentColor?
    @Binding var selection: SelectionValue
    @ViewBuilder let content: () -> Content

    init(
        titleKey: LocalizedStringKey,
        systemImage: String,
        accent: AppAccentColor? = nil,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.accent = accent
        _selection = selection
        self.content = content
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(OneCartPalette.primaryAccent(for: colorScheme, accent: accent))
                .frame(width: 28, height: 28)
                .background(
                    OneCartPalette.primarySoft(for: colorScheme, accent: accent),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            Picker(titleKey, selection: $selection) {
                content()
            }
            .pickerStyle(.menu)
            .tint(.secondary)
        }
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.35), value: accent)
    }
}

struct AccountAccentPickerRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: AppAccentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "paintpalette.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(OneCartPalette.primaryAccent(for: colorScheme, accent: selection))
                    .frame(width: 28, height: 28)
                    .background(
                        OneCartPalette.primarySoft(for: colorScheme, accent: selection),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                Text("settings.accent_color")
                    .font(.body)

                Spacer(minLength: 0)
            }

            HStack(spacing: 0) {
                ForEach(AppAccentColor.allCases) { color in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selection = color
                        }
                        CartHaptics.light()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(color.swatchColor)
                                .frame(width: 38, height: 38)
                                .shadow(color: Color.black.opacity(0.08), radius: 2, y: 1)

                            if selection == color {
                                Circle()
                                    .strokeBorder(.white, lineWidth: 2.5)
                                    .frame(width: 38, height: 38)
                                    .transition(.opacity)

                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .transition(.opacity)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(color.localizedTitleKey))
                }
            }
            .padding(.vertical, 2)
        }
        .padding(.vertical, 4)
    }
}

struct AccountAppIconPickerRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: AppIconOption
    var accent: AppAccentColor?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "app.dashed")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(OneCartPalette.primaryAccent(for: colorScheme, accent: accent))
                    .frame(width: 28, height: 28)
                    .background(
                        OneCartPalette.primarySoft(for: colorScheme, accent: accent),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                Text("settings.app_icon")
                    .font(.body)

                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                ForEach(AppIconOption.allCases) { option in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selection = option
                        }
                        CartHaptics.light()
                        Task {
                            _ = await AppIconManager.setAlternateIcon(to: option)
                        }
                    } label: {
                        ZStack {
                            Image(option.previewImageName)
                                .resizable()
                                .aspectRatio(1, contentMode: .fit)
                                .frame(width: 54, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                                )
                                .shadow(
                                    color: selection == option
                                        ? OneCartPalette.primary(for: colorScheme, accent: accent).opacity(0.35)
                                        : Color.black.opacity(0.08),
                                    radius: selection == option ? 6 : 3,
                                    y: 2
                                )

                            if selection == option {
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .strokeBorder(
                                        OneCartPalette.primary(for: colorScheme, accent: accent),
                                        lineWidth: 2.5
                                    )
                                    .frame(width: 60, height: 60)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(option.localizedTitleKey))
                }
            }
            .padding(.vertical, 2)
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.35), value: accent)
    }
}
