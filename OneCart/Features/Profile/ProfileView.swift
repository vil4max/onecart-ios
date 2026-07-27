import PhotosUI
import SwiftUI
import UIKit

// MARK: - Local profile media

enum ProfileMediaStore {
    enum Kind: String {
        case avatar
        case banner
    }

    static func image(for userID: UUID, kind: Kind) -> UIImage? {
        let url = fileURL(for: userID, kind: kind)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func save(_ image: UIImage, for userID: UUID, kind: Kind) throws {
        let data = try encodedJPEG(from: image, kind: kind)
        try ensureDirectory(for: userID)
        try data.write(to: fileURL(for: userID, kind: kind), options: .atomic)
    }

    /// Compact JPEG suitable for Storage or data-URL fallback in profiles.
    static func encodedJPEG(from image: UIImage, kind: Kind) throws -> Data {
        let maxDimension: CGFloat
        let quality: CGFloat
        switch kind {
        case .avatar:
            maxDimension = 360
            quality = 0.72
        case .banner:
            maxDimension = 960
            quality = 0.70
        }
        let prepared = image.oneCartResized(maxDimension: maxDimension)
        guard let data = prepared.jpegData(compressionQuality: quality) else {
            throw ProfileMediaError.encodeFailed
        }
        // Keep fallback data-URLs under practical DB/metadata limits.
        if data.count > (kind == .avatar ? 90000 : 140_000),
           let tighter = prepared.jpegData(compressionQuality: 0.55)
        {
            return tighter
        }
        return data
    }

    static func remove(for userID: UUID, kind: Kind) {
        let url = fileURL(for: userID, kind: kind)
        try? FileManager.default.removeItem(at: url)
    }

    static func jpegData(for userID: UUID, kind: Kind) throws -> Data {
        let url = fileURL(for: userID, kind: kind)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            throw ProfileMediaError.encodeFailed
        }
        return data
    }

    private static func directory(for userID: UUID) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OneCartProfiles", isDirectory: true)
            .appendingPathComponent(userID.uuidString, isDirectory: true)
    }

    private static func fileURL(for userID: UUID, kind: Kind) -> URL {
        directory(for: userID).appendingPathComponent("\(kind.rawValue).jpg")
    }

    private static func ensureDirectory(for userID: UUID) throws {
        try FileManager.default.createDirectory(
            at: directory(for: userID),
            withIntermediateDirectories: true
        )
    }
}

enum ProfileMediaError: LocalizedError {
    case encodeFailed

    var errorDescription: String? {
        String(localized: "profile.save_image_failed")
    }
}

extension UIImage {
    func oneCartResized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Decodes `data:image/...;base64,...` media strings (Storage URLs use AsyncImage).
    static func oneCartImage(fromMedia raw: String?) -> UIImage? {
        guard let raw, raw.hasPrefix("data:image/"),
              let comma = raw.firstIndex(of: ",") else { return nil }
        let encoded = String(raw[raw.index(after: comma)...])
        guard let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) else {
            return nil
        }
        return UIImage(data: data)
    }
}

// MARK: - Profile editor

struct ProfileEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var avatarImage: UIImage?
    @State private var bannerImage: UIImage?
    @State private var avatarRemoved = false
    @State private var bannerRemoved = false
    @State private var picking: ProfileMediaStore.Kind?
    @State private var validationMessage: String?

    init(account: OneCartAccount, avatar: UIImage?, banner: UIImage?) {
        _displayName = State(initialValue: account.displayName)
        _avatarImage = State(initialValue: avatar)
        _bannerImage = State(initialValue: banner)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    bannerSection
                    identitySection
                    nameSection
                    if let validationMessage {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundColor(OneCartPalette.danger)
                    }
                    Text("profile.privacy_note")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(OneCartPalette.background.ignoresSafeArea())
            .navigationTitle("profile.nav_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") {
                        Task { await save() }
                    }
                    .font(.body.weight(.semibold))
                    .disabled(model.isBusy || !canSave)
                }
            }
            .sheet(item: $picking) { kind in
                PhotoLibraryPicker { image in
                    applyPicked(image, kind: kind)
                }
            }
        }
    }

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var bannerSection: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let bannerImage {
                    Image(uiImage: bannerImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [
                            OneCartPalette.primary.opacity(0.85),
                            OneCartPalette.primaryStrong,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay(
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 148)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Menu {
                Button {
                    picking = .banner
                } label: {
                    Label("profile.choose_photo", systemImage: "photo")
                }
                if bannerImage != nil {
                    Button(role: .destructive) {
                        bannerImage = nil
                        bannerRemoved = true
                    } label: {
                        Label("profile.remove_banner", systemImage: "trash")
                    }
                }
            } label: {
                Label("profile.banner", systemImage: "camera.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.45), in: Capsule())
            }
            .padding(12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "profile.banner_a11y"))
    }

    private var identitySection: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                ProfileAvatarView(
                    name: displayName,
                    image: avatarImage,
                    size: 88
                )
                .overlay(
                    Circle()
                        .stroke(OneCartPalette.background, lineWidth: 4)
                )

                Menu {
                    Button {
                        picking = .avatar
                    } label: {
                        Label("profile.choose_photo", systemImage: "photo")
                    }
                    if avatarImage != nil {
                        Button(role: .destructive) {
                            avatarImage = nil
                            avatarRemoved = true
                        } label: {
                            Label("profile.remove_photo", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(OneCartPalette.primary, in: Circle())
                        .overlay(Circle().stroke(OneCartPalette.background, lineWidth: 2))
                }
                .accessibilityLabel(String(localized: "profile.change_avatar_a11y"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? String(localized: "profile.name_placeholder_empty")
                    : displayName)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("profile.personal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("profile.tap_photo_hint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, -36)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("profile.name_label")
                .font(.caption.weight(.semibold))
                .foregroundColor(OneCartPalette.primary)
                .textCase(.uppercase)

            TextField("profile.name_field_placeholder", text: $displayName)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .padding(14)
                .background(
                    OneCartPalette.surface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        }
    }

    private func applyPicked(_ image: UIImage?, kind: ProfileMediaStore.Kind) {
        guard let image else { return }
        switch kind {
        case .avatar:
            avatarImage = image
            avatarRemoved = false
        case .banner:
            bannerImage = image
            bannerRemoved = false
        }
    }

    private func save() async {
        validationMessage = nil
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationMessage = String(localized: "profile.validation_empty_name")
            return
        }
        let ok = await model.updateProfile(
            displayName: trimmed,
            avatar: avatarImage,
            banner: bannerImage,
            removeAvatar: avatarRemoved && avatarImage == nil,
            removeBanner: bannerRemoved && bannerImage == nil
        )
        if ok {
            dismiss()
        }
    }
}

// MARK: - Shared avatar

struct ProfileAvatarView: View {
    let name: String
    var image: UIImage?
    /// HTTPS Storage URL or `data:image/...;base64,...`
    var remoteURL: String?
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let remoteImage = UIImage.oneCartImage(fromMedia: remoteURL) {
                Image(uiImage: remoteImage)
                    .resizable()
                    .scaledToFill()
            } else if let remoteURL, let url = URL(string: remoteURL), !remoteURL.hasPrefix("data:") {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(remote):
                        remote
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        initialsView
                            .overlay(ProgressView().scaleEffect(0.7))
                    case .failure:
                        initialsView
                    @unknown default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(name)
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OneCartPalette.primary)
    }

    private var initials: String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let value = words.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "?" : value.uppercased()
    }
}

// MARK: - PHPicker

private struct PhotoLibraryPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: PHPickerViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, dismiss: dismiss)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage?) -> Void
        let dismiss: DismissAction

        init(onPick: @escaping (UIImage?) -> Void, dismiss: DismissAction) {
            self.onPick = onPick
            self.dismiss = dismiss
        }

        func picker(_: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self)
            else {
                onPick(nil)
                dismiss()
                return
            }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async {
                    self.onPick(object as? UIImage)
                    self.dismiss()
                }
            }
        }
    }
}

extension ProfileMediaStore.Kind: Identifiable {
    var id: String {
        rawValue
    }
}
