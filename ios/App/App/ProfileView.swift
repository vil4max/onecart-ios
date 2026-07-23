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
        if data.count > (kind == .avatar ? 90_000 : 140_000),
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
        "Не удалось сохранить изображение."
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
        NavigationView {
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
                    Text("Имя, аватар и баннер хранятся только на этом устройстве и не синхронизируются с группой через iCloud.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(OneCartPalette.background.ignoresSafeArea())
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
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
        .navigationViewStyle(.stack)
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
                    Label("Выбрать фото", systemImage: "photo")
                }
                if bannerImage != nil {
                    Button(role: .destructive) {
                        bannerImage = nil
                        bannerRemoved = true
                    } label: {
                        Label("Убрать баннер", systemImage: "trash")
                    }
                }
            } label: {
                Label("Баннер", systemImage: "camera.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.45), in: Capsule())
            }
            .padding(12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Баннер профиля")
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
                        Label("Выбрать фото", systemImage: "photo")
                    }
                    if avatarImage != nil {
                        Button(role: .destructive) {
                            avatarImage = nil
                            avatarRemoved = true
                        } label: {
                            Label("Убрать фото", systemImage: "trash")
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
                .accessibilityLabel("Изменить аватар")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Ваше имя"
                    : displayName)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("Личный профиль")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Нажмите на фото, чтобы заменить")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, -36)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Имя")
                .font(.caption.weight(.semibold))
                .foregroundColor(OneCartPalette.primary)
                .textCase(.uppercase)

            TextField("Как вас видят в группе", text: $displayName)
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
            validationMessage = "Укажите имя."
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
    var image: UIImage? = nil
    /// HTTPS Storage URL or `data:image/...;base64,...`
    var remoteURL: String? = nil
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
                    case .success(let remote):
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

struct ProfileBannerView: View {
    var image: UIImage? = nil
    /// HTTPS Storage URL or `data:image/...;base64,...`
    var remoteURL: String? = nil
    var height: CGFloat = 120
    /// When false, empty state is still the app default (always visible).
    var useAppDefaultWhenEmpty: Bool = true

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
            } else if let remoteURL,
                      let url = URL(string: remoteURL),
                      !remoteURL.hasPrefix("data:")
            {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let remote):
                        remote.resizable().scaledToFill()
                    case .empty:
                        defaultBanner
                            .overlay(ProgressView().tint(.white.opacity(0.85)))
                    case .failure:
                        defaultBanner
                    @unknown default:
                        defaultBanner
                    }
                }
            } else if useAppDefaultWhenEmpty {
                defaultBanner
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .accessibilityHidden(true)
    }

    /// Built-in OneCart banner when the member has not set a custom one.
    private var defaultBanner: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 52 / 255, green: 120 / 255, blue: 91 / 255),
                    Color(red: 32 / 255, green: 82 / 255, blue: 62 / 255),
                    Color(red: 24 / 255, green: 48 / 255, blue: 40 / 255),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Soft decorative shapes — calm utility, not loud branding.
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 160, height: 160)
                .offset(x: 110, y: -40)
            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 110, height: 110)
                .offset(x: -100, y: 50)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: 180, height: 80)
                .rotationEffect(.degrees(-12))
                .offset(x: -40, y: 10)

            VStack(spacing: 6) {
                Image(systemName: "cart.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                Text("OneCart")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white.opacity(0.88))
            }
            .padding(.bottom, 4)
        }
    }
}

// MARK: - PHPicker (iOS 15+)

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
                  provider.canLoadObject(ofClass: UIImage.self) else {
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
    var id: String { rawValue }
}
