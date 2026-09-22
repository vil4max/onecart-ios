import SwiftUI

/// Initials on the accent colour, or the remote avatar when the account has one.
struct MemberAvatarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var size = 40.0
    let name: String
    var remoteURL: String?
    var accent: AppAccentColor?

    var body: some View {
        Group {
            if let remoteURL, let url = URL(string: remoteURL), url.scheme == "https" {
                AsyncImage(url: url) { phase in
                    if case let .success(remote) = phase {
                        remote.resizable().scaledToFill()
                    } else {
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OneCartPalette.primary(for: colorScheme, accent: accent))
    }

    private var initials: String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let value = words.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "?" : value.uppercased()
    }
}

struct AccountMemberRow: View {
    let member: FamilyMember
    var accent: AppAccentColor?

    var body: some View {
        HStack(spacing: 12) {
            MemberAvatarView(name: member.displayName, remoteURL: member.avatarURL, accent: accent)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                    if member.isCurrentUser {
                        Text("common.you")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(member.access.isOwner ? "cart.owner_role" : "cart.member_role")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A row of glass swatches; the selection shows a check and reads as selected to VoiceOver.
struct AccentColorPickerRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var swatchSize = 40.0
    @Binding var selection: AppAccentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("settings.accent_color")

            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        ForEach(AppAccentColor.allCases) { color in
                            Button {
                                withAnimation(.snappy) { selection = color }
                            } label: {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.white)
                                    .opacity(selection == color ? 1 : 0)
                                    .frame(width: swatchSize, height: swatchSize)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(
                                .regular
                                    .tint(OneCartPalette.primary(for: colorScheme, accent: color))
                                    .interactive(),
                                in: .circle
                            )
                            .accessibilityLabel(Text(color.localizedTitleKey))
                            .accessibilityAddTraits(selection == color ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Icon previews with their names; the selection carries the accent ring.
struct AppIconPickerRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var previewSize = 56.0
    let selection: AppIconOption
    var accent: AppAccentColor?
    let onSelect: (AppIconOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("settings.app_icon")

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(AppIconOption.allCases) { option in
                        Button {
                            onSelect(option)
                        } label: {
                            VStack(spacing: 6) {
                                Image(option.previewImageName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: previewSize, height: previewSize)
                                    .clipShape(.rect(cornerRadius: previewSize * 0.22))
                                    .padding(3)
                                    .overlay {
                                        if selection == option {
                                            RoundedRectangle(cornerRadius: previewSize * 0.22 + 3)
                                                .strokeBorder(
                                                    OneCartPalette.primary(for: colorScheme, accent: accent),
                                                    lineWidth: 2.5
                                                )
                                        }
                                    }
                                Text(option.localizedTitleKey)
                                    .font(.caption)
                                    .foregroundStyle(selection == option ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(option.localizedTitleKey))
                        .accessibilityAddTraits(selection == option ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// One-field editor for the cart name and the display name.
struct NameEditorSheet: View {
    let titleKey: LocalizedStringKey
    let placeholderKey: LocalizedStringKey
    let promptKey: LocalizedStringKey
    let saveKey: LocalizedStringKey
    @Binding var text: String
    var requiresText = false
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(placeholderKey, text: $text)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                } footer: {
                    Text(promptKey)
                }
            }
            .navigationTitle(titleKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveKey, action: onSave)
                        .disabled(requiresText && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
