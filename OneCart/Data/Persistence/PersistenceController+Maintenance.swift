import CloudKit
import CoreData
import Foundation
import OSLog

extension PersistenceController {
    func copyStoreFilesForDiagnostics() throws -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let diagnosticsRoot = storeDirectoryURL
            .appendingPathComponent("OneCart-diagnostics", isDirectory: true)
            .appendingPathComponent(stamp, isDirectory: true)
        try FileManager.default.createDirectory(
            at: diagnosticsRoot,
            withIntermediateDirectories: true
        )

        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: storeDirectoryURL,
            includingPropertiesForKeys: nil
        )
        for url in contents {
            let name = url.lastPathComponent
            guard name.lowercased().hasPrefix("onecart-") else { continue }
            if name.lowercased().hasPrefix("onecart-diagnostics") { continue }
            let destination = diagnosticsRoot.appendingPathComponent(name)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: url, to: destination)
        }
        logger.info("Diagnostics snapshot written to \(diagnosticsRoot.path, privacy: .public)")
        return diagnosticsRoot
    }

    func hardResetPersistentStores() throws {
        guard !inMemory else { return }

        loadLock.lock()
        loaded = false
        loading = false
        privateStore = nil
        sharedStore = nil
        let waiters = loadWaiters
        loadWaiters.removeAll()
        loadLock.unlock()
        waiters.forEach { $0.resume(returning: .failure(PersistenceError.storeNotLoaded(.private))) }

        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            if let url = store.url {
                try? coordinator.destroyPersistentStore(at: url, ofType: store.type, options: nil)
            } else {
                try? coordinator.remove(store)
            }
        }

        Self.removeAllOneCartStoreFiles(in: storeDirectoryURL)

        container = Self.makeContainer()
        container.persistentStoreDescriptions = Self.makeStoreDescriptions(
            directory: storeDirectoryURL,
            inMemory: false,
            cloudKitEnabled: cloudKitEnabled
        )
    }

    func resetLocalStoreFiles() throws {
        try hardResetPersistentStores()
    }

    static func shouldWipeLocalStoresForCloudKitEnvironment(
        previous: String?,
        current: String,
        storeFilesExist: Bool,
        isDebugProcess: Bool
    ) -> Bool {
        _ = storeFilesExist
        _ = isDebugProcess
        guard let previous else { return false }
        return previous != current
    }

    func reconcileCloudKitEnvironmentBeforeLoad() throws {
        guard !inMemory, cloudKitEnabled else { return }

        let current = CloudKitShareEnvironment.process.rawValue
        let previous = UserDefaults.standard.string(forKey: Self.cloudKitLocalEnvironmentKey)
        let storeFilesExist = Self.oneCartStoreFilesExist(in: storeDirectoryURL)
        #if DEBUG
            let isDebugProcess = true
        #else
            let isDebugProcess = false
        #endif

        guard Self.shouldWipeLocalStoresForCloudKitEnvironment(
            previous: previous,
            current: current,
            storeFilesExist: storeFilesExist,
            isDebugProcess: isDebugProcess
        ) else { return }

        logger.error(
            "CloudKit env mismatch wipe previous=\(previous ?? "nil", privacy: .public) current=\(current, privacy: .public) storeFilesExist=\(storeFilesExist)"
        )
        CartSyncLog.action.error(
            "cloudKitEnvWipe previous=\(previous ?? "nil", privacy: .public) current=\(current, privacy: .public)"
        )
        _ = try? copyStoreFilesForDiagnostics()
        Self.removeAllOneCartStoreFiles(in: storeDirectoryURL)
        UserDefaults.standard.removeObject(forKey: Self.cloudKitLocalEnvironmentKey)
    }

    func stampCloudKitEnvironmentAfterSuccessfulLoad() {
        guard !inMemory, cloudKitEnabled else { return }
        UserDefaults.standard.set(
            CloudKitShareEnvironment.process.rawValue,
            forKey: Self.cloudKitLocalEnvironmentKey
        )
    }

    static func oneCartStoreFilesExist(in directory: URL) -> Bool {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return false }
        return contents.contains { url in
            let name = url.lastPathComponent.lowercased()
            guard name.hasPrefix("onecart-") else { return false }
            return !name.hasPrefix("onecart-diagnostics")
        }
    }

    static func removeAllOneCartStoreFiles(in directory: URL) {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in contents {
            let name = url.lastPathComponent.lowercased()
            guard name.hasPrefix("onecart-") else { continue }
            if name.hasPrefix("onecart-diagnostics") { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    static func scope(forStoreURL url: URL?) -> PersistentStoreScope? {
        guard let name = url?.lastPathComponent.lowercased() else { return nil }
        if name.contains("private") { return .private }
        if name.contains("shared") { return .shared }
        return nil
    }
}
