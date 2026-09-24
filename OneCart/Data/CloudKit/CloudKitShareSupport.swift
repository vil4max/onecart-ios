import CloudKit
import UIKit

enum CloudKitShareEnvironment: String {
    case production
    case development
    case unknown

    static var process: CloudKitShareEnvironment {
        .production
    }

    static func fromDiagnostic(_ text: String) -> CloudKitShareEnvironment {
        let normalized = text.lowercased()
        if normalized.contains("environment=production")
            || normalized.contains("environment: production")
            || normalized.contains(", environment=production")
        {
            return .production
        }
        if normalized.contains("environment=sandbox")
            || normalized.contains("environment=development")
            || normalized.contains("environment: sandbox")
            || normalized.contains("environment: development")
        {
            return .development
        }
        return .unknown
    }

    static func diagnostic(for share: CKShare) -> String {
        var parts = [String(describing: share)]
        for key in privateContainerKeys {
            if let value = guardedValue(forKey: key, of: share) {
                parts.append("\(key)=\(String(describing: value))")
            }
        }
        return parts.joined(separator: " ")
    }

    /// Undocumented CKShare accessors that may disappear in any OS release. KVC on a missing key
    /// raises an Objective-C exception Swift cannot catch, so each key is read only while the
    /// share still responds to its getter; otherwise the description alone decides.
    static let privateContainerKeys = ["containerID", "containerIdentifier", "_containerID"]

    /// Test seam: same guard as `diagnostic(for:)`, for arbitrary keys.
    static func guardedValue(forKey key: String, of share: CKShare) -> Any? {
        guard share.responds(to: NSSelectorFromString(key)) else { return nil }
        return share.value(forKey: key)
    }

    static func of(_ share: CKShare) -> CloudKitShareEnvironment {
        fromDiagnostic(diagnostic(for: share))
    }

    static func canMutateInProcess(_ share: CKShare) -> Bool {
        let shareEnvironment = of(share)
        if shareEnvironment == .unknown {
            return true
        }
        return shareEnvironment == process
    }
}

enum OneCartShareBranding {
    static let title = "OneCart Family"

    @discardableResult
    static func apply(to share: CKShare) -> Bool {
        var changed = false
        if (share[CKShare.SystemFieldKey.title] as? String) != title {
            share[CKShare.SystemFieldKey.title] = title as CKRecordValue
            changed = true
        }
        if share[CKShare.SystemFieldKey.thumbnailImageData] == nil {
            share[CKShare.SystemFieldKey.thumbnailImageData] = thumbnailImageData as CKRecordValue
            changed = true
        }
        return changed
    }

    static let thumbnailImage: UIImage = {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let rgb = OneCartPalette.currentAccent.primaryRGB.light
            UIColor(red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, alpha: 1).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 112).fill()

            if let mark = UIImage(named: "LaunchIcon") {
                let inset = CGRect(x: 80, y: 80, width: 352, height: 352)
                mark.draw(in: inset)
            } else {
                let config = UIImage.SymbolConfiguration(pointSize: 220, weight: .semibold)
                if let symbol = UIImage(systemName: "cart.fill", withConfiguration: config)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal)
                {
                    let origin = CGPoint(
                        x: (size.width - symbol.size.width) / 2,
                        y: (size.height - symbol.size.height) / 2
                    )
                    symbol.draw(at: origin)
                }
            }
        }
    }()

    static let thumbnailImageData: Data = thumbnailImage.pngData() ?? Data()
}

enum OneCartShareLinkJoin {
    @discardableResult
    static func applyReadWriteACL(to share: CKShare, reopenInviteDoor: Bool = false) -> Bool {
        var changed = false
        let mayTouchPublicPermission = reopenInviteDoor || share.publicPermission != .none
        if mayTouchPublicPermission, share.publicPermission != .readWrite {
            share.publicPermission = .readWrite
            changed = true
        }
        if ShareParticipantRules.grantReadWrite(to: share.participants) {
            changed = true
        }
        return changed
    }
}

/// What share mutations read and change on one participant. `CKShare.Participant` has no public
/// initializer, so this seam lets tests drive the decisions below with plain objects; the
/// CloudKit type is the only production conformer. Class-bound because a permission change must
/// land on the participant the share holds.
protocol ShareParticipantHandle: AnyObject {
    var userRecordName: String? { get }
    var lookupEmailAddress: String? { get }
    var lookupPhoneNumber: String? { get }
    var isOwner: Bool { get }
    var permission: CKShare.ParticipantPermission { get set }
}

extension CKShare.Participant: ShareParticipantHandle {
    var userRecordName: String? {
        userIdentity.userRecordID?.recordName
    }

    var lookupEmailAddress: String? {
        userIdentity.lookupInfo?.emailAddress
    }

    var lookupPhoneNumber: String? {
        userIdentity.lookupInfo?.phoneNumber
    }

    var isOwner: Bool {
        role == .owner
    }
}

/// Participant decisions of the share mutations, free of CloudKit I/O.
enum ShareParticipantRules {
    /// The identity CloudKit exposes for a participant (REQ-SHARE-040): record name, then lookup
    /// email, then lookup phone number — the same order the members list and removal both use, so
    /// a listed member always resolves to the participant that produced its row. A record name or
    /// email that CloudKit reports as an empty string is not skipped in favor of the next kind:
    /// only a missing (`nil`) value falls through, matching the members list's existing guard that
    /// drops a row on an empty key rather than resolving it against a lower-priority identity.
    static func memberKey(for participant: some ShareParticipantHandle) -> String? {
        participant.userRecordName ?? participant.lookupEmailAddress ?? participant.lookupPhoneNumber
    }

    /// The participant a members-list row stands for (REQ-SHARE-040): the row id is the stable
    /// UUID of `memberKey(for:)`.
    static func participant<Participant: ShareParticipantHandle>(
        forMemberID memberID: UUID,
        in participants: [Participant]
    ) -> Participant? {
        participants.first { participant in
            memberKey(for: participant).map(FamilyInviteLinkBuilder.stableUUID(for:)) == memberID
        }
    }

    /// Every non-owner participant may edit the cart (REQ-SHARE-020); the owner is never touched.
    /// Returns whether any permission changed.
    static func grantReadWrite(to participants: [some ShareParticipantHandle]) -> Bool {
        var changed = false
        for participant in participants where !participant.isOwner {
            guard participant.permission != .readWrite else { continue }
            participant.permission = .readWrite
            changed = true
        }
        return changed
    }
}

/// Unstructured workers let the caller finish even when an SDK callback ignores cancellation.
enum CloudKitDeadline {
    static func run<Value: Sendable>(
        timeoutNanoseconds: UInt64,
        timeoutError: Error = OneCartCloudKitError.shareTimedOut,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await run(
            timeout: { try await Task.sleep(nanoseconds: timeoutNanoseconds) },
            timeoutError: timeoutError,
            operation: operation
        )
    }

    static func run<Value: Sendable>(
        timeout: @escaping @Sendable () async throws -> Void,
        timeoutError: Error = OneCartCloudKitError.shareTimedOut,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let gate = DeadlineResultGate<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard gate.install(continuation) else { return }
                let work = Task {
                    do { try await gate.resolve(.success(operation())) } catch { gate.resolve(.failure(error)) }
                }
                let timer = Task {
                    do {
                        try await timeout()
                        try Task.checkCancellation()
                        gate.resolve(.failure(timeoutError))
                    } catch {}
                }
                gate.setTasks([work, timer])
            }
        } onCancel: {
            gate.resolve(.failure(CancellationError()))
        }
    }
}

private final class DeadlineResultGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?
    private var tasks: [Task<Void, Never>] = []

    func install(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func setTasks(_ tasks: [Task<Void, Never>]) {
        lock.lock()
        let finished = result != nil
        if !finished {
            self.tasks = tasks
        }
        lock.unlock()
        if finished {
            tasks.forEach { $0.cancel() }
        }
    }

    func resolve(_ result: Result<Value, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = continuation
        self.continuation = nil
        let tasks = tasks
        self.tasks = []
        lock.unlock()
        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }
}
