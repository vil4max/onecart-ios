import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingProfile = false
    @State private var sharePayload: CartSharePayload?
    @State private var isSharing = false
    @State private var shareAlert: String?

    var body: some View {
        NavigationView {
            List {
                Button {
                    showingProfile = true
                } label: {
                    Label("👤 Мой профиль", systemImage: "person.crop.circle")
                }
                .disabled(model.account == nil)

                Button {
                    model.showFamilyManagement()
                } label: {
                    Label("👥 Кто в корзине", systemImage: "person.2")
                }

                if model.access?.isOwner == true {
                    Button {
                        shareCart()
                    } label: {
                        HStack {
                            Label("🔗 Пригласить семью", systemImage: "square.and.arrow.up")
                            Spacer()
                            if isSharing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isSharing || !model.isOnline)
                }

                Button(role: .destructive) {
                    model.signOut()
                } label: {
                    Label("🚪 Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .navigationTitle("Ещё")
            .sheet(isPresented: $showingProfile) {
                if let account = model.account {
                    ProfileEditorSheet(
                        account: account,
                        avatar: model.profileAvatar,
                        banner: model.profileBanner
                    )
                }
            }
            .sheet(item: $sharePayload) { payload in
                CartActivityViewController(
                    activityItems: [CartInviteActivityItem(link: payload.link)]
                )
            }
            .alert(
                "OneCart",
                isPresented: Binding(
                    get: { shareAlert != nil },
                    set: { if !$0 { shareAlert = nil } }
                )
            ) {
                Button("OK", role: .cancel) { shareAlert = nil }
            } message: {
                Text(shareAlert ?? "")
            }
        }
        .navigationViewStyle(.stack)
    }

    private func shareCart() {
        guard !isSharing else { return }
        isSharing = true
        let work = Task { @MainActor in
            defer { isSharing = false }
            do {
                let link: FamilyInviteLink
                if let cached = model.preparedInviteLink,
                   cached.expiresAt > Date().addingTimeInterval(30)
                {
                    link = cached
                } else {
                    link = try await model.createFamilyInviteLink()
                }
                guard !Task.isCancelled else { return }
                sharePayload = CartSharePayload(link: link)
            } catch is CancellationError {
                return
            } catch {
                shareAlert = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 24_000_000_000)
            guard !work.isCancelled else { return }
            if isSharing {
                work.cancel()
                isSharing = false
                shareAlert = OneCartCloudKitError.shareTimedOut.errorDescription
            }
        }
    }
}
