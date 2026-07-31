import Foundation
import UserNotifications

enum MemberJoinNotifier {
    private static func seenKey(accountID: UUID) -> String {
        "onecart.seen-member-ids.\(accountID.uuidString)"
    }

    static func notifyNewMembersIfNeeded(
        previousIDs: Set<UUID>,
        current: [FamilyMember],
        accountID: UUID,
        defaults: UserDefaults
    ) {
        let stored = storedIDs(accountID: accountID, defaults: defaults)
        let diff = MemberJoinDiff.evaluate(
            previousIDs: previousIDs,
            storedIDs: stored,
            current: current
        )
        defaults.set(diff.nextStoredIDs.map(\.uuidString), forKey: seenKey(accountID: accountID))
        guard diff.shouldNotify, !diff.newcomerIDs.isEmpty else { return }

        let newcomers = current.filter { diff.newcomerIDs.contains($0.id) }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            else { return }
            for member in newcomers {
                let content = UNMutableNotificationContent()
                content.title = String(localized: "notify.member_joined_title")
                content.body = String(
                    localized: "notify.member_joined_body \(member.displayName)"
                )
                content.sound = .default
                let request = UNNotificationRequest(
                    identifier: "member-joined-\(member.id.uuidString)",
                    content: content,
                    trigger: nil
                )
                center.add(request)
            }
        }
    }

    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    private static func storedIDs(accountID: UUID, defaults: UserDefaults) -> Set<UUID> {
        Set(
            (defaults.array(forKey: seenKey(accountID: accountID)) as? [String] ?? [])
                .compactMap(UUID.init(uuidString:))
        )
    }
}

enum MemberJoinDiff {
    struct Result {
        var newcomerIDs: [UUID]
        var nextStoredIDs: Set<UUID>
        var shouldNotify: Bool
    }

    static func evaluate(
        previousIDs: Set<UUID>,
        storedIDs: Set<UUID>,
        current: [FamilyMember]
    ) -> Result {
        let currentIDs = Set(current.map(\.id))
        if previousIDs.isEmpty, storedIDs.isEmpty {
            return Result(newcomerIDs: [], nextStoredIDs: currentIDs, shouldNotify: false)
        }
        let baseline = previousIDs.isEmpty ? storedIDs : previousIDs.union(storedIDs)
        let newcomerIDs = current
            .filter { !baseline.contains($0.id) && !$0.isCurrentUser }
            .map(\.id)
        return Result(
            newcomerIDs: newcomerIDs,
            nextStoredIDs: currentIDs,
            shouldNotify: true
        )
    }
}
