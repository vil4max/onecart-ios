import CoreData
import Foundation

/// A member's chosen name, shared with everyone in the cart (REQ-AUTH-040). It belongs to the
/// cart's `FamilySpace`, so CloudKit keeps it in the cart's zone next to the products.
@objc(MemberProfileEntity)
final class MemberProfileEntity: NSManagedObject {
    @NSManaged var id: UUID?
    /// The member's CloudKit user record name, as `CKShare.Participant` reports it to others.
    @NSManaged var userRecordName: String?
    @NSManaged var displayName: String?
    @NSManaged var createdAt: Date?
    @NSManaged var updatedAt: Date?
    @NSManaged var deletedAt: Date?
    @NSManaged var familySpace: FamilySpace?

    @nonobjc class func fetchRequest() -> NSFetchRequest<MemberProfileEntity> {
        NSFetchRequest<MemberProfileEntity>(entityName: "MemberProfile")
    }

    var updatedDate: Date {
        updatedAt ?? createdAt ?? .distantPast
    }

    var isDeletedValue: Bool {
        deletedAt != nil
    }
}

extension MemberProfileEntity: SoftDeletable, Timestamped {}

enum MemberProfileNames {
    /// Names by user record name. Two devices of one member can each create a row before they
    /// see the other's, so the newest living row per member decides; a blank name means none.
    static func latest(from profiles: [MemberProfileEntity]) -> [String: String] {
        var newest: [String: MemberProfileEntity] = [:]
        for profile in profiles where !profile.isDeletedValue {
            guard let recordName = profile.userRecordName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !recordName.isEmpty
            else { continue }
            if let current = newest[recordName], !isPreferred(profile, over: current) {
                continue
            }
            newest[recordName] = profile
        }
        return newest.compactMapValues { profile in
            let name = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? nil : name
        }
    }

    static func latest(in family: FamilySpace) -> [String: String] {
        latest(from: family.memberProfiles?.allObjects as? [MemberProfileEntity] ?? [])
    }

    /// Newest `updatedAt` wins; the stable ID breaks ties so every device picks the same row.
    static func isPreferred(_ candidate: MemberProfileEntity, over current: MemberProfileEntity) -> Bool {
        if candidate.updatedDate != current.updatedDate {
            return candidate.updatedDate > current.updatedDate
        }
        return (candidate.id?.uuidString ?? "") > (current.id?.uuidString ?? "")
    }
}
