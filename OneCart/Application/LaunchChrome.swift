import SwiftUI
import UIKit

enum LaunchChromeLayout {
    static let cartSize: CGFloat = 112
    static let titleTopPadding: CGFloat = 28
    static let titleFontSize: CGFloat = 22
    static let minimumPeekDuration: Double = 0.45
    static let driveOutDuration: Double = 0.85

    static var offscreenLeading: CGFloat {
        -cartSize
    }

    static func cartLeading(width: CGFloat, progress: CGFloat) -> CGFloat {
        let start = offscreenLeading
        let end = width
        return start + (end - start) * progress
    }
}

struct LaunchCartRideView: View {
    @EnvironmentObject private var model: AppSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onFinished: () -> Void

    @State private var driveProgress: CGFloat = 0
    @State private var titleOpacity: CGFloat = 1

    var body: some View {
        LaunchCartRideUIView(
            progress: driveProgress,
            titleOpacity: titleOpacity
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "common.loading"))
        .accessibilityAddTraits(.updatesFrequently)
        .task { await runRide() }
    }

    @MainActor
    private func runRide() async {
        async let ready: Bool = waitUntilAppReady()
        do {
            try await Task.sleep(
                nanoseconds: UInt64(LaunchChromeLayout.minimumPeekDuration * 1_000_000_000)
            )
        } catch {
            return
        }
        guard await ready else { return }

        if reduceMotion {
            onFinished()
            return
        }

        driveProgress = 1
        titleOpacity = 0

        do {
            try await Task.sleep(
                nanoseconds: UInt64((LaunchChromeLayout.driveOutDuration + 0.04) * 1_000_000_000)
            )
        } catch {
            onFinished()
            return
        }
        onFinished()
    }

    @MainActor
    private func waitUntilAppReady() async -> Bool {
        if model.isReady {
            return true
        }
        for await ready in model.$isReady.values {
            if Task.isCancelled {
                return false
            }
            if ready {
                return true
            }
        }
        return false
    }
}

private struct LaunchCartRideUIView: UIViewRepresentable {
    var progress: CGFloat
    var titleOpacity: CGFloat

    func makeUIView(context _: Context) -> LaunchRideView {
        LaunchRideView()
    }

    func updateUIView(_ uiView: LaunchRideView, context _: Context) {
        uiView.apply(progress: progress, titleOpacity: titleOpacity)
    }
}

private final class LaunchRideView: UIView {
    private let titleLabel = UILabel()
    private let cartView = UIImageView()
    private var cartLeadingConstraint: NSLayoutConstraint?
    private var cartCenterYConstraint: NSLayoutConstraint?
    private var appliedProgress: CGFloat = 0
    private var pendingProgress: CGFloat = 0
    private var pendingTitleOpacity: CGFloat = 1
    private var driveAnimator: UIViewPropertyAnimator?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "LaunchBackground")
        isUserInteractionEnabled = false
        insetsLayoutMarginsFromSafeArea = false

        titleLabel.text = String(localized: "common.app_name")
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: LaunchChromeLayout.titleFontSize, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        cartView.image = UIImage(named: "LaunchIcon")
        cartView.contentMode = .scaleAspectFit
        cartView.clipsToBounds = true
        cartView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(cartView)

        let cartLeading = cartView.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: LaunchChromeLayout.offscreenLeading
        )
        cartLeadingConstraint = cartLeading

        let initialMidY = Self.screenBounds.height / 2
        let cartCenterY = cartView.centerYAnchor.constraint(
            equalTo: topAnchor,
            constant: initialMidY
        )
        cartCenterYConstraint = cartCenterY

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.topAnchor.constraint(
                equalTo: safeAreaLayoutGuide.topAnchor,
                constant: LaunchChromeLayout.titleTopPadding
            ),
            cartCenterY,
            cartLeading,
            cartView.widthAnchor.constraint(equalToConstant: LaunchChromeLayout.cartSize),
            cartView.heightAnchor.constraint(equalToConstant: LaunchChromeLayout.cartSize),
        ])
    }

    private static var screenBounds: CGRect {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let scene = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first
        {
            return scene.screen.bounds
        }
        return .init(x: 0, y: 0, width: 390, height: 844)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(progress: CGFloat, titleOpacity: CGFloat) {
        pendingProgress = progress
        pendingTitleOpacity = titleOpacity
        guard bounds.width > 0 else { return }
        commitPending(animated: progress > appliedProgress)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        syncCartCenterYToScreen()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        syncCartCenterYToScreen()
        guard bounds.width > 0, driveAnimator == nil else { return }
        commitPending(animated: false)
    }

    private func syncCartCenterYToScreen() {
        let screenMidY: CGFloat = if let window {
            convert(CGPoint(x: 0, y: window.bounds.midY), from: window).y
        } else {
            Self.screenBounds.midY
        }
        if cartCenterYConstraint?.constant != screenMidY {
            cartCenterYConstraint?.constant = screenMidY
        }
    }

    private func commitPending(animated: Bool) {
        let width = screenWidth
        let leading = LaunchChromeLayout.cartLeading(width: width, progress: pendingProgress)
        let opacity = pendingTitleOpacity

        if !animated || pendingProgress <= appliedProgress {
            driveAnimator?.stopAnimation(true)
            driveAnimator = nil
            titleLabel.alpha = opacity
            cartLeadingConstraint?.constant = leading
            appliedProgress = pendingProgress
            return
        }

        appliedProgress = pendingProgress
        driveAnimator?.stopAnimation(true)

        let timing = UICubicTimingParameters(
            controlPoint1: CGPoint(x: 0.22, y: 0.08),
            controlPoint2: CGPoint(x: 0.18, y: 1.0)
        )
        let animator = UIViewPropertyAnimator(
            duration: LaunchChromeLayout.driveOutDuration,
            timingParameters: timing
        )
        animator.addAnimations {
            self.titleLabel.alpha = opacity
            self.cartLeadingConstraint?.constant = leading
            self.layoutIfNeeded()
        }
        animator.addCompletion { [weak self] _ in
            self?.driveAnimator = nil
        }
        driveAnimator = animator
        animator.startAnimation()
    }

    private var screenWidth: CGFloat {
        if let window {
            return window.bounds.width
        }
        return bounds.width
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
            Text("common.app_name")
                .font(compact ? .title3.bold() : .title2.bold())
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "common.app_name"))
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
            .foregroundColor(OneCartPalette.primaryAccent)
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
