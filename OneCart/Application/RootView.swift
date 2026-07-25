import SwiftUI

enum OneCartPalette {
    static let primary = Color(red: 52 / 255, green: 120 / 255, blue: 91 / 255)
    static let primaryStrong = Color(red: 40 / 255, green: 95 / 255, blue: 71 / 255)
    static let primarySoft = Color(red: 225 / 255, green: 239 / 255, blue: 231 / 255)
    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let danger = Color(red: 185 / 255, green: 74 / 255, blue: 72 / 255)
}

private enum RootPhase: Equatable {
    case loading
    case welcome
    case main
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Cart overlay stays up until the ride ends; only then the real UI mounts.
    @State private var cartRideFinished = false

    private var phase: RootPhase {
        if !model.isReady {
            return .loading
        }
        if model.needsWelcome {
            return .welcome
        }
        return .main
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                if cartRideFinished {
                    destinationView
                        .transition(.opacity)
                } else {
                    OneCartPalette.background.ignoresSafeArea()
                }
            }
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.4),
                value: cartRideFinished
            )

            if !cartRideFinished {
                LaunchCartRideView {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
                        cartRideFinished = true
                    }
                }
                .transition(.opacity)
                .zIndex(4)
            }

            if let toast = model.toast {
                ToastBanner(message: toast)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(5)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: model.toast)
        .sheet(isPresented: $model.familyManagementPresented) {
            FamilyManagementSheet(model: model)
        }
        .sheet(item: $model.pendingCartMerge) { prompt in
            CartMergeSheet(prompt: prompt)
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch phase {
        case .loading:
            OneCartPalette.background.ignoresSafeArea()
        case .welcome:
            WelcomeView(model: model)
        case .main:
            MainTabView()
        }
    }
}

/// Lightweight cart ride on a solid background. Destination UI mounts only after
/// this finishes, so the heavy main screen is not animating under an opaque veil.
private struct LaunchCartRideView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onFinished: () -> Void

    /// Only `travel` is animated — keeps the ride smooth on the main thread.
    @State private var travel: CGFloat = -1.15

    private let driveInDuration: Double = 0.9
    private let driveOutDuration: Double = 0.55
    private let cartWidth: CGFloat = 92

    var body: some View {
        GeometryReader { geo in
            let travelX = travel * (geo.size.width * 0.8)

            ZStack {
                OneCartPalette.background.ignoresSafeArea()

                Image("LaunchCart")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: cartWidth)
                    .offset(x: travelX)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Загрузка OneCart")
        .accessibilityAddTraits(.updatesFrequently)
        .task { await runRide() }
    }

    @MainActor
    private func runRide() async {
        if reduceMotion {
            travel = 0
            guard await waitUntilAppReady() else { return }
            onFinished()
            return
        }

        withAnimation(.timingCurve(0.2, 0.82, 0.24, 1, duration: driveInDuration)) {
            travel = 0
        }
        do {
            try await Task.sleep(nanoseconds: UInt64(driveInDuration * 1_000_000_000))
        } catch {
            return
        }

        guard await waitUntilAppReady() else { return }

        withAnimation(.timingCurve(0.4, 0.02, 0.2, 1, duration: driveOutDuration)) {
            travel = 1.35
        }
        do {
            try await Task.sleep(nanoseconds: UInt64((driveOutDuration + 0.03) * 1_000_000_000))
        } catch {
            onFinished()
            return
        }
        onFinished()
    }

    @MainActor
    private func waitUntilAppReady() async -> Bool {
        if model.isReady { return true }
        for await ready in model.$isReady.values {
            if Task.isCancelled { return false }
            if ready { return true }
        }
        return false
    }
}

struct MainTabView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SyncStatusBanner()
            TabView {
                HomeView(model: model)
                    .tabItem { Label("tab.home", systemImage: "cart.fill") }
                StoresView()
                    .tabItem { Label("tab.stores", systemImage: "storefront.fill") }
                HistoryView()
                    .tabItem { Label("tab.history", systemImage: "clock.arrow.circlepath") }
                SettingsView()
                    .tabItem { Label("tab.settings", systemImage: "gearshape.fill") }
            }
            .tint(OneCartPalette.primary)
        }
        .background(OneCartPalette.background)
    }
}

private struct SyncStatusBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let state = model.syncState
        if state != .synchronized {
            HStack(spacing: 8) {
                Image(systemName: state.systemImage)
                Text(statusText(for: state))
                    .font(.footnote.weight(.medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(foreground(for: state))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background(for: state))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(statusText(for: state))
        }
    }

    private func statusText(for state: OneCartSyncState) -> String {
        if state == .failed {
            let detail = model.lastSyncError?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !detail.isEmpty { return detail }
        }
        return state.title
    }

    private func foreground(for state: OneCartSyncState) -> Color {
        switch state {
        case .failed: OneCartPalette.danger
        case .offline: Color.orange
        default: OneCartPalette.primaryStrong
        }
    }

    private func background(for state: OneCartSyncState) -> Color {
        switch state {
        case .failed: OneCartPalette.danger.opacity(0.12)
        case .offline: Color.orange.opacity(0.12)
        default: OneCartPalette.primarySoft
        }
    }
}

struct OneCartMark: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 10 : 12) {
            Image(systemName: "cart.fill")
                .font(.system(size: compact ? 16 : 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: compact ? 36 : 40, height: compact ? 36 : 40)
                .background(
                    OneCartPalette.primary,
                    in: RoundedRectangle(cornerRadius: compact ? 11 : 12, style: .continuous)
                )
            Text("OneCart")
                .font(compact ? .title3.bold() : .title2.bold())
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("OneCart")
    }
}

struct ToastBanner: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: message.style.systemImage)
                .foregroundColor(accentColor)
            Text(message.text)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 420, alignment: .leading)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }

    private var accentColor: Color {
        switch message.style {
        case .success: OneCartPalette.primary
        case .info: .blue
        case .error: OneCartPalette.danger
        }
    }
}

struct OneCartPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                configuration.isPressed
                    ? OneCartPalette.primaryStrong
                    : OneCartPalette.primary,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

struct OneCartSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(OneCartPalette.primaryStrong)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                OneCartPalette.primarySoft.opacity(configuration.isPressed ? 0.72 : 1),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}

extension View {
    func oneCartCard() -> some View {
        padding(16)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
    }
}
