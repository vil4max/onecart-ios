import SwiftUI

struct HomeView: View {
    let viewModel: CartViewModel

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.hasActiveFamilySpace {
                    householdBootstrapContent
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(OneCartPalette.background.ignoresSafeArea())
                        .navigationTitle(viewModel.cartTitle)
                        .navigationBarTitleDisplayMode(.inline)
                        .task(id: viewModel.householdBootstrapTaskID) {
                            await viewModel.ensureHouseholdCartIfNeeded()
                        }
                } else if viewModel.primaryListID != nil {
                    ShoppingListView(viewModel: viewModel)
                } else {
                    ScrollView {
                        HomeEmptyCartPanel(
                            cartName: viewModel.cartTitle
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    .refreshable {
                        await viewModel.sync(reason: .pull)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(OneCartPalette.background.ignoresSafeArea())
                    .navigationTitle(viewModel.cartTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            if viewModel.isCartSyncing {
                                ProgressView()
                                    .controlSize(.mini)
                                    .accessibilityLabel(Text("cart.updating"))
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var householdBootstrapContent: some View {
        if viewModel.householdCartBootstrapFailed {
            HomeConnectFailedPanel {
                Task { await viewModel.retryHouseholdCartBootstrap() }
            }
        } else {
            HomeConnectingCartPanel()
        }
    }
}

private struct HomeConnectingCartPanel: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("home.connecting_cart")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            OneCartPalette.surface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }
}

private struct HomeConnectFailedPanel: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("home.connect_failed_title")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("home.connect_failed_message")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("welcome.try_again", action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            OneCartPalette.surface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }
}

private struct HomeEmptyCartPanel: View {
    let cartName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(cartName)
                .font(.title2.bold())
            Text("home.empty_hint")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            OneCartPalette.surface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .padding(.top, 8)
    }
}

struct HomePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
