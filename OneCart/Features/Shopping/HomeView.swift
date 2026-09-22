import SwiftUI

struct HomeView: View {
    let viewModel: CartViewModel

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.hasActiveFamilySpace {
                    householdBootstrapContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(OneCartPalette.background.ignoresSafeArea())
                        .navigationTitle(viewModel.cartTitle)
                        .task(id: viewModel.householdBootstrapTaskID) {
                            await viewModel.ensureHouseholdCartIfNeeded()
                        }
                } else if viewModel.primaryListID != nil {
                    ShoppingListView(viewModel: viewModel)
                } else {
                    ScrollView {
                        ContentUnavailableView {
                            Label("cart.empty_title", systemImage: "cart.badge.plus")
                        } description: {
                            Text("home.empty_hint")
                        }
                        .containerRelativeFrame(.vertical)
                    }
                    .refreshable {
                        await viewModel.sync(reason: .pull)
                    }
                    .background(OneCartPalette.background.ignoresSafeArea())
                    .navigationTitle(viewModel.cartTitle)
                    .toolbar {
                        if viewModel.isCartSyncing {
                            ToolbarItem(placement: .topBarTrailing) {
                                ProgressView()
                                    .controlSize(.small)
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
            ContentUnavailableView {
                Label("home.connect_failed_title", systemImage: "icloud.slash")
            } description: {
                Text("home.connect_failed_message")
            } actions: {
                Button("welcome.try_again") {
                    Task { await viewModel.retryHouseholdCartBootstrap() }
                }
                .buttonStyle(.borderedProminent)
                .tint(OneCartPalette.primary)
            }
        } else {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("home.connecting_cart")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .accessibilityElement(children: .combine)
        }
    }
}
