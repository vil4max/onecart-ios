import Foundation
@testable import OneCart
import Testing

@MainActor
final class RecordingHaptics: HapticsPlaying {
    enum Event: Equatable {
        case light
        case success
        case error
    }

    private(set) var events: [Event] = []

    func light() {
        events.append(.light)
    }

    func success() {
        events.append(.success)
    }

    func error() {
        events.append(.error)
    }
}

@MainActor
@Suite("InviteShareControllerTests")
struct InviteShareControllerTests {
    @MainActor
    final class Gate {
        var isOpen = false
    }

    private let membership = FakeMembershipManager()
    private let haptics = RecordingHaptics()
    private let clock = TestClock()

    private func makeController() -> InviteShareController {
        InviteShareController(membership: membership, haptics: haptics, clock: clock.appClock)
    }

    private static func link(_ path: String) throws -> FamilyInviteLink {
        let url = try #require(URL(string: "https://example.com/\(path)"))
        return FamilyInviteLink(id: UUID(), familyName: "Family", url: url)
    }

    @Test("REQ-SHARE-110: a share hands the link to the share sheet with light then success haptics")
    func successHandsOutLink() async throws {
        let link = try Self.link("i")
        membership.inviteLinkResult = .success(link)
        let controller = makeController()

        controller.share()
        for _ in 0..<1000 where controller.isSharing {
            await Task.yield()
        }

        #expect(controller.sharePayload?.link == link)
        #expect(controller.alert == nil)
        #expect(haptics.events == [.light, .success])
        #expect(clock.pendingSleepers == 0)
    }

    @Test("REQ-SHARE-030: the watchdog on the injected clock times out a hung share")
    func watchdogTimesOutOnTheClock() async throws {
        membership.inviteLinkOperation = {
            try await Task.sleep(for: .seconds(3600))
            throw CancellationError()
        }
        let controller = makeController()

        controller.share()
        #expect(await clock.waitForSleepers())
        clock.advance(by: InviteShareController.defaultTimeout - .seconds(1))
        await Task.yield()
        #expect(controller.isSharing)

        clock.advance(by: .seconds(1))
        for _ in 0..<1000 where controller.isSharing {
            await Task.yield()
        }

        #expect(!controller.isSharing)
        #expect(controller.alert == .error(try #require(OneCartCloudKitError.shareTimedOut.errorDescription)))
        #expect(controller.sharePayload == nil)
        #expect(haptics.events == [.light])
    }

    @Test("REQ-SHARE-030: an error after the timeout neither replaces the timeout alert nor plays the error haptic")
    func lateErrorAfterTimeoutIsIgnored() async throws {
        struct LateFailure: Error {}
        let failed = Gate()
        membership.inviteLinkOperation = {
            while !Task.isCancelled {
                await Task.yield()
            }
            failed.isOpen = true
            throw LateFailure()
        }
        let controller = makeController()

        controller.share()
        #expect(await clock.waitForSleepers())
        clock.advance(by: InviteShareController.defaultTimeout)
        for _ in 0..<10_000 where !failed.isOpen {
            await Task.yield()
        }
        await Task.yield()

        #expect(failed.isOpen)
        #expect(controller.alert == .error(try #require(OneCartCloudKitError.shareTimedOut.errorDescription)))
        #expect(membership.describedErrors.isEmpty)
        #expect(haptics.events == [.light])
    }

    @Test("REQ-SHARE-030: a timed-out share that answers late cannot touch the newer share")
    func generationGuardKeepsNewerShare() async throws {
        let firstLink = try Self.link("first")
        let secondLink = try Self.link("second")
        let releaseFirst = Gate()
        let releaseSecond = Gate()
        membership.inviteLinkOperation = { [membership] in
            // Neither request honours cancellation, like a server call that answers anyway.
            if membership.createInviteLinkCount == 1 {
                while !releaseFirst.isOpen {
                    await Task.yield()
                }
                return firstLink
            }
            while !releaseSecond.isOpen {
                await Task.yield()
            }
            return secondLink
        }
        let controller = makeController()

        controller.share()
        #expect(await clock.waitForSleepers())
        clock.advance(by: InviteShareController.defaultTimeout)
        for _ in 0..<1000 where controller.isSharing {
            await Task.yield()
        }
        #expect(!controller.isSharing)
        controller.alert = nil

        controller.share()
        #expect(controller.isSharing)
        releaseFirst.isOpen = true
        for _ in 0..<1000 {
            await Task.yield()
        }

        #expect(controller.isSharing)
        #expect(controller.sharePayload == nil)
        #expect(controller.alert == nil)

        releaseSecond.isOpen = true
        for _ in 0..<1000 where controller.isSharing {
            await Task.yield()
        }
        #expect(controller.sharePayload?.link == secondLink)
        #expect(controller.alert == nil)
    }
}
