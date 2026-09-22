import Foundation
@testable import OneCart
import SwiftUI
import Testing
import UIKit

/// One accessibility element of a hosted screen, flattened from the UIKit view tree and the
/// SwiftUI accessibility nodes that `_UIHostingView` exposes through `accessibilityElements`.
struct HostedAccessibilityElement {
    let label: String?
    let identifier: String?
    let value: String?
    let traits: UIAccessibilityTraits
    /// The node itself, kept so a test can activate a button the way an assistive client would.
    let node: NSObject

    var isButton: Bool {
        traits.contains(.button)
    }

    var isEnabled: Bool {
        !traits.contains(.notEnabled)
    }

    var isSelected: Bool {
        traits.contains(.selected)
    }

    /// Presses the element through `UIAccessibility`; false when the node declines the action.
    @discardableResult
    @MainActor
    func activate() -> Bool {
        node.accessibilityActivate()
    }
}

/// Mounts a SwiftUI screen in a `UIHostingController` inside a visible `UIWindow` so the body
/// executes with a real layout pass; tests read the result back as accessibility elements.
///
/// Layout is settled with bounded run-loop turns; nothing sleeps for a fixed duration.
@MainActor
final class HostedView {
    static let phoneSize = CGSize(width: 393, height: 852)

    /// SwiftUI materializes its accessibility nodes only while the process-level accessibility
    /// flag is on, the flag an assistive client (VoiceOver, XCUITest) sets when it connects.
    /// Unit tests have no client, so the test process sets it once through libAccessibility.
    /// Test-only: the symbol never ships in the app, and a missing symbol fails every hosted
    /// test loudly instead of yielding an empty tree.
    private static let accessibilityTreeEnabled: Bool = {
        typealias SetEnabled = @convention(c) (Bool) -> Void
        guard let library = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(library, "_AXSApplicationAccessibilitySetEnabled")
        else { return false }
        unsafeBitCast(symbol, to: SetEnabled.self)(true)
        return true
    }()

    let window: UIWindow
    let controller: UIViewController

    init(_ content: some View, size: CGSize = HostedView.phoneSize) {
        if !Self.accessibilityTreeEnabled {
            Issue
                .record(
                    "libAccessibility could not enable the accessibility tree; hosted assertions would read nothing"
                )
        }
        let controller = UIHostingController(rootView: content)
        let window = if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0 is UIWindowScene }) as? UIWindowScene
        {
            UIWindow(windowScene: scene)
        } else {
            UIWindow(frame: CGRect(origin: .zero, size: size))
        }
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = controller
        window.isHidden = false
        self.window = window
        self.controller = controller
        settle()
    }

    /// Runs layout and short run-loop turns so lists materialize their rows and `.task` /
    /// `.onAppear` work scheduled on the main actor gets to run.
    func settle(turns: Int = 2) {
        for _ in 0 ..< turns {
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    /// Pumps until the condition holds or the budget is spent: one run-loop turn for layout and
    /// one yield so main-actor tasks started by a button action get to run. The main queue is
    /// not reentrant, so a nested `RunLoop.run` alone never executes those tasks.
    @discardableResult
    func pump(maxTurns: Int = 40, until condition: () -> Bool) async -> Bool {
        for _ in 0 ..< maxTurns {
            if condition() {
                return true
            }
            settle(turns: 1)
            await Task.yield()
        }
        return condition()
    }

    /// Scrolls every scroll view to its end so a `List` or `Form` materializes its last rows,
    /// the way a person reaches them; cells outside the viewport do not exist yet.
    func scrollToBottom() {
        for scrollView in views(of: UIScrollView.self) {
            let bottom = scrollView.contentSize.height + scrollView.adjustedContentInset.bottom
                - scrollView.bounds.height
            scrollView.setContentOffset(CGPoint(x: 0, y: max(0, bottom)), animated: false)
        }
        settle(turns: 1)
    }

    /// Detaches the screen; the window is released with the fixture, this only hides it early.
    func tearDown() {
        window.isHidden = true
        window.rootViewController = nil
    }

    // MARK: - Accessibility tree

    var elements: [HostedAccessibilityElement] {
        var visited = Set<ObjectIdentifier>()
        var result: [HostedAccessibilityElement] = []
        collect(from: window, visited: &visited, into: &result)
        return result
    }

    var buttons: [HostedAccessibilityElement] {
        elements.filter(\.isButton)
    }

    var labels: [String] {
        elements.compactMap(\.label)
    }

    var identifiers: [String] {
        elements.compactMap(\.identifier)
    }

    /// A destructive button also yields a label-less wrapper node with the same identifier;
    /// the control itself is the node that carries a label or the button trait.
    func element(identifier: String) -> HostedAccessibilityElement? {
        let matches = elements(identifier: identifier)
        return matches.first { $0.label != nil || $0.isButton } ?? matches.first
    }

    func elements(identifier: String) -> [HostedAccessibilityElement] {
        elements.filter { $0.identifier == identifier }
    }

    func element(label: String) -> HostedAccessibilityElement? {
        elements.first { $0.label == label }
    }

    func containsLabel(_ label: String) -> Bool {
        labels.contains(label)
    }

    /// True when any label or value contains the fragment, case- and diacritic-insensitively.
    func containsText(_ fragment: String) -> Bool {
        elements.contains { element in
            [element.label, element.value].contains { text in
                text?.range(of: fragment, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    // MARK: - UIKit views

    /// UIKit-native pieces (navigation bar titles, tab bars, platform buttons) are not part of
    /// the SwiftUI accessibility tree, so tests read them from the view hierarchy.
    func views<T: UIView>(of _: T.Type) -> [T] {
        var result: [T] = []
        func walk(_ view: UIView) {
            if let match = view as? T {
                result.append(match)
            }
            view.subviews.forEach(walk)
        }
        walk(window)
        return result
    }

    var uiLabelTexts: [String] {
        views(of: UILabel.self).compactMap(\.text)
    }

    private func collect(
        from object: NSObject,
        visited: inout Set<ObjectIdentifier>,
        into result: inout [HostedAccessibilityElement]
    ) {
        guard visited.insert(ObjectIdentifier(object)).inserted else { return }
        if object.isAccessibilityElement {
            result.append(snapshot(of: object))
        }
        if let children = object.accessibilityElements {
            for case let child as NSObject in children {
                collect(from: child, visited: &visited, into: &result)
            }
        }
        if let view = object as? UIView {
            for subview in view.subviews {
                collect(from: subview, visited: &visited, into: &result)
            }
        }
    }

    private func snapshot(of object: NSObject) -> HostedAccessibilityElement {
        HostedAccessibilityElement(
            label: object.accessibilityLabel,
            identifier: identifier(of: object),
            value: object.accessibilityValue,
            traits: object.accessibilityTraits,
            node: object
        )
    }

    /// SwiftUI's nodes answer `accessibilityIdentifier` by selector without adopting
    /// `UIAccessibilityIdentification`, so the identifier is read through key-value coding.
    private func identifier(of object: NSObject) -> String? {
        if let identified = object as? UIAccessibilityIdentification {
            return identified.accessibilityIdentifier
        }
        guard object.responds(to: NSSelectorFromString("accessibilityIdentifier")) else { return nil }
        return object.value(forKey: "accessibilityIdentifier") as? String
    }
}
