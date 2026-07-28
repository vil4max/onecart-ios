import CloudKit
import CoreData
import Foundation

extension PersistenceController {
    static func makeContainer() -> NSPersistentCloudKitContainer {
        let model = OneCartManagedObjectModel.makeModel()
        return NSPersistentCloudKitContainer(name: "OneCart", managedObjectModel: model)
    }

    static func makeStoreDescriptions(
        directory: URL,
        inMemory: Bool,
        cloudKitEnabled: Bool
    ) -> [NSPersistentStoreDescription] {
        [
            makeStoreDescription(
                scope: .private,
                directory: directory,
                inMemory: inMemory,
                cloudKitEnabled: cloudKitEnabled
            ),
            makeStoreDescription(
                scope: .shared,
                directory: directory,
                inMemory: inMemory,
                cloudKitEnabled: cloudKitEnabled
            ),
        ]
    }

    static func makeStoreDescription(
        scope: PersistentStoreScope,
        directory: URL,
        inMemory: Bool,
        cloudKitEnabled: Bool
    ) -> NSPersistentStoreDescription {
        let fileName = scope == .private ? "OneCart-private.sqlite" : "OneCart-shared.sqlite"
        let description: NSPersistentStoreDescription

        if inMemory {
            description = NSPersistentStoreDescription(
                url: directory.appendingPathComponent(fileName)
            )
            description.type = NSSQLiteStoreType
            description.shouldAddStoreAsynchronously = false
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        } else {
            description = NSPersistentStoreDescription(
                url: directory.appendingPathComponent(fileName)
            )
            description.type = NSSQLiteStoreType
            description.shouldAddStoreAsynchronously = false
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true

            if cloudKitEnabled {
                let cloudKitOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: cloudKitContainerIdentifier
                )
                cloudKitOptions.databaseScope = scope == .private ? .private : .shared
                description.cloudKitContainerOptions = cloudKitOptions
            }

            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(
                true as NSNumber,
                forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
            )
        }

        return description
    }
}
