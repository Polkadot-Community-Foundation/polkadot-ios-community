import Foundation
import Keystore_iOS
import Products

protocol LocalStateErasing {
    func eraseUserDefaults()
    func eraseDatabases() throws
}

/// Erases the local state a device backup carries: the standard and App Group UserDefaults suites, the
/// DotNs content cache suite, and the CoreData directory. The directory is removed from disk without going
/// through the storage facades — it runs before any store is opened, and `CoreDataService` recreates the
/// directory (backup-excluded) on first use. Not for use while a store is open.
final class LocalStateEraser: LocalStateErasing {
    private let sharedSuiteName: String
    private let databaseDirectoryURLs: [URL]
    private let fileManager: FileManager
    private let logger: LoggerProtocol

    init(
        sharedSuiteName: String = SharedContainerGroup.name,
        databaseDirectoryURLs: [URL] = [
            UserStorageParams.sharedStorageDirectoryURL,
            SubstrateStorageParams.sharedStorageDirectoryURL
        ],
        fileManager: FileManager = .default,
        logger: LoggerProtocol
    ) {
        self.sharedSuiteName = sharedSuiteName
        self.databaseDirectoryURLs = databaseDirectoryURLs
        self.fileManager = fileManager
        self.logger = logger
    }

    func eraseUserDefaults() {
        SettingsManager.shared.removeAll()

        for suiteName in [sharedSuiteName, ContentHashCache.suiteName] {
            let defaults = UserDefaults(suiteName: suiteName)
            defaults?.removePersistentDomain(forName: suiteName)
            defaults?.synchronize()
        }
    }

    func eraseDatabases() throws {
        let directories = Set(databaseDirectoryURLs.map(\.standardizedFileURL))
        for directory in directories {
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory)
            guard exists, isDirectory.boolValue else {
                continue
            }

            try fileManager.removeItem(at: directory)
            logger.info("Removed the CoreData directory \(directory.lastPathComponent)")
        }
    }
}
