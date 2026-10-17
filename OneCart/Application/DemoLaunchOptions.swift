#if DEBUG
    import SwiftUI

    /// Demo and test switches, parsed from the launch arguments once at the app root and handed
    /// to the views through the environment, so no production view reads `ProcessInfo`. DEBUG
    /// builds only: the Release binary carries no demo switch, not even its name (App Review
    /// Guideline 2.5.19), so every reader sits under `#if DEBUG` too.
    struct DemoLaunchOptions: Equatable, Sendable {
        static let demoUIArgument = "-oneCartDemoUI"
        /// Opens the add composer when the cart appears, for screenshots.
        static let composerArgument = "-oneCartDemoComposer"
        /// Opens the newest History day, for screenshots.
        static let historyDetailArgument = "-oneCartDemoHistoryDetail"
        /// On the simulator, turns a failed Sign in with Apple into the debug test-account sign-in.
        /// Opt-in: without it the failure and Retry UI shows as on a device.
        static let simulatorTestAccountFallbackArgument = "-oneCartSimulatorTestAccountFallback"

        var isDemoUI = false
        var opensComposer = false
        var opensNewestHistoryDay = false
        var fallsBackToTestAccountOnSimulator = false

        static let none = DemoLaunchOptions()

        init(
            isDemoUI: Bool = false,
            opensComposer: Bool = false,
            opensNewestHistoryDay: Bool = false,
            fallsBackToTestAccountOnSimulator: Bool = false
        ) {
            self.isDemoUI = isDemoUI
            self.opensComposer = opensComposer
            self.opensNewestHistoryDay = opensNewestHistoryDay
            self.fallsBackToTestAccountOnSimulator = fallsBackToTestAccountOnSimulator
        }

        init(arguments: [String]) {
            let flags = Set(arguments)
            isDemoUI = flags.contains(Self.demoUIArgument)
            opensComposer = flags.contains(Self.composerArgument)
            opensNewestHistoryDay = flags.contains(Self.historyDetailArgument)
            fallsBackToTestAccountOnSimulator = flags.contains(Self.simulatorTestAccountFallbackArgument)
        }
    }

    extension EnvironmentValues {
        @Entry var demoLaunchOptions: DemoLaunchOptions = .none
    }
#endif
