import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingProfile = false

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
                    Button {} label: {
                        Label("🔗 Пригласить семью", systemImage: "square.and.arrow.up")
                    }
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
        }
        .navigationViewStyle(.stack)
    }
}
