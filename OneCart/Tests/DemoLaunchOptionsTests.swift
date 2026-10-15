import Foundation
@testable import OneCart
import Testing

@Suite("DemoLaunchOptionsTests")
struct DemoLaunchOptionsTests {
    @Test("REQ-AUTH-010: a launch without demo arguments turns every demo switch off")
    func plainLaunchHasNoSwitches() {
        let options = DemoLaunchOptions(arguments: ["OneCart", "-AppleLanguages", "(en)"])
        #expect(options == .none)
    }

    @Test("REQ-AUTH-010: each demo argument turns on its own switch")
    func eachArgumentMapsToItsSwitch() {
        #expect(DemoLaunchOptions(arguments: ["-oneCartDemoUI"]) == DemoLaunchOptions(isDemoUI: true))
        #expect(DemoLaunchOptions(arguments: ["-oneCartDemoComposer"]) == DemoLaunchOptions(opensComposer: true))
        #expect(
            DemoLaunchOptions(arguments: ["-oneCartDemoHistoryDetail"])
                == DemoLaunchOptions(opensNewestHistoryDay: true))
        #expect(
            DemoLaunchOptions(arguments: ["-oneCartSimulatorTestAccountFallback"])
                == DemoLaunchOptions(fallsBackToTestAccountOnSimulator: true))
    }

    @Test("REQ-AUTH-010: the demo UI alone does not turn a failed sign-in into the test account")
    func testAccountFallbackIsOptIn() {
        let demo = DemoLaunchOptions(arguments: ["-oneCartDemoUI", "-oneCartDemoRole", "welcome", "-oneCartDemoReset"])
        #expect(demo.isDemoUI)
        #expect(!demo.fallsBackToTestAccountOnSimulator)
        #expect(!demo.opensComposer)
        #expect(!demo.opensNewestHistoryDay)
    }
}
