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
    @Environment(AppSession.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onFinished: () -> Void

    @State private var driveProgress: CGFloat = 0
    @State private var titleOpacity: CGFloat = 1

    var body: some View {
        LaunchCartRideUIView(
            progress: driveProgress,
            titleOpacity: titleOpacity,
            accent: model.preferences.accentColor
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("common.loading"))
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
        for await ready in Observations({ model.isReady }) {
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
    var accent: AppAccentColor

    func makeUIView(context _: Context) -> LaunchRideView {
        LaunchRideView(accent: accent)
    }

    func updateUIView(_ uiView: LaunchRideView, context _: Context) {
        uiView.updateAccent(accent)
        uiView.apply(progress: progress, titleOpacity: titleOpacity)
    }
}

private final class LaunchRideView: UIView {
    private let titleLabel = UILabel()
    private let cartView = UIImageView()
    private var cartLeadingConstraint: NSLayoutConstraint?
    private var appliedProgress: CGFloat = 0
    private var pendingProgress: CGFloat = 0
    private var pendingTitleOpacity: CGFloat = 1
    private var driveAnimator: UIViewPropertyAnimator?
    private var accent: AppAccentColor

    init(accent: AppAccentColor = OneCartPalette.currentAccent) {
        self.accent = accent
        super.init(frame: .zero)
        setupView()
    }

    override init(frame: CGRect) {
        accent = OneCartPalette.currentAccent
        super.init(frame: frame)
        setupView()
    }

    func updateAccent(_ newAccent: AppAccentColor) {
        guard accent != newAccent else { return }
        accent = newAccent
        updateBackgroundColor()
    }

    private func updateBackgroundColor() {
        backgroundColor = UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            let rgb = dark ? self.accent.primaryRGB.dark : self.accent.primaryRGB.light
            return UIColor(
                red: rgb.0 / 255,
                green: rgb.1 / 255,
                blue: rgb.2 / 255,
                alpha: 1
            )
        }
    }

    private func setupView() {
        updateBackgroundColor()
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

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.topAnchor.constraint(
                equalTo: safeAreaLayoutGuide.topAnchor,
                constant: LaunchChromeLayout.titleTopPadding
            ),
            // The view covers its scene (`ignoresSafeArea` in `RootView`), so its own centre is
            // the scene's centre whatever the window size; no screen or device size is assumed.
            cartView.centerYAnchor.constraint(equalTo: centerYAnchor),
            cartLeading,
            cartView.widthAnchor.constraint(equalToConstant: LaunchChromeLayout.cartSize),
            cartView.heightAnchor.constraint(equalToConstant: LaunchChromeLayout.cartSize),
        ])
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

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, driveAnimator == nil else { return }
        commitPending(animated: false)
    }

    /// Runs only once the view has a width (`apply` and `layoutSubviews` check it), so the
    /// drive-out ends past the view's own trailing edge.
    private func commitPending(animated: Bool) {
        let leading = LaunchChromeLayout.cartLeading(width: bounds.width, progress: pendingProgress)
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
}
