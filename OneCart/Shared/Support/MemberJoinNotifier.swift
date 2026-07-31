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
        let currentIDs = Set(current.map(\.id))
        let stored = Set(
            (defaults.array(forKey: seenKey(accountID: accountID)) as? [String] ?? [])
                .compactMap(UUID.init(uuidString:))
        )
        let baseline = previousIDs.isEmpty ? stored : previousIDs.union(stored)
        let newcomers = current.filter { !baseline.contains($0.id) && !$0.isCurrentUser }
        defaults.set(currentIDs.map(\.uuidString), forKey: seenKey(accountID: accountID))
        guard !newcomers.isEmpty else { return }

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
}
