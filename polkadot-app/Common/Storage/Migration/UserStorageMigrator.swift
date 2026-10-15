import CoreData
import Foundation

final class UserStorageMigrator {
    let modelDirectory: String
    let model: UserStorageVersion
    let storeURL: URL
    let fileManager: FileManager

    init(
        storeURL: URL,
        modelDirectory: String,
        model: UserStorageVersion,
        fileManager: FileManager
    ) {
        self.storeURL = storeURL
        self.model = model
        self.modelDirectory = modelDirectory
        self.fileManager = fileManager
    }
}

// MARK: - StorageMigrating

extension UserStorageMigrator: StorageMigrating {
    func requiresMigration() -> Bool {
        checkIfMigrationNeeded(
            to: UserStorageParams.modelVersion,
            storeURL: storeURL,
            fileManager: fileManager,
            modelDirectory: modelDirectory
        )
    }

    func performMigration() {
        let destinationVersion = UserStorageParams.modelVersion

        let mom = createManagedObjectModel(
            forResource: destinationVersion.rawValue,
            modelDirectory: modelDirectory
        )

        let psc = NSPersistentStoreCoordinator(managedObjectModel: mom)
        // Persistent history tracking is enabled on the live store
        // (UserDataStorageFacade). Opening it here without this option
        // makes Core Data treat the store as read-only, and the v23 → v24
        // lightweight migration then fails with SQLite's misleading
        // "attempt to write a readonly database".
        let options: [AnyHashable: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true,
            NSPersistentHistoryTrackingKey: true
        ]

        do {
            try addPersistentStore(to: psc, options: options)
        } catch where Self.isUnmigratableStore(error) {
            // The model that wrote this store is no longer shipped, so nothing can migrate it.
            // Keys and funds are not stored here (the entropy is in the keychain and coins are
            // re-derived from the chain), so recreate it; local-only state such as chats is lost.
            (Logger.shared as LoggerProtocol).error(
                "User store predates \(destinationVersion.rawValue) and cannot be migrated, "
                    + "recreating it: \(error)"
            )

            try? psc.destroyPersistentStore(
                at: storeURL,
                ofType: NSSQLiteStoreType,
                options: options
            )

            do {
                try addPersistentStore(to: psc, options: options)
            } catch {
                fatalError("Failed to recreate persistent store: \(error)")
            }
        } catch {
            fatalError("Failed to migrate persistent store: \(error)")
        }
    }

    func migrate(_ completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performMigration()

            DispatchQueue.main.async {
                completion()
            }
        }
    }
}

// MARK: - Error classification

extension UserStorageMigrator {
    /// True only when the model that wrote the store is no longer shipped. Transient failures
    /// (disk full, permissions, a locked file) must not match, or recoverable data is destroyed.
    static func isUnmigratableStore(_ error: Error) -> Bool {
        let error = error as NSError

        guard error.domain == NSCocoaErrorDomain else {
            return false
        }

        return error.code == NSPersistentStoreIncompatibleVersionHashError
            || error.code == NSMigrationMissingSourceModelError
    }
}

// MARK: - Private

private extension UserStorageMigrator {
    func addPersistentStore(
        to coordinator: NSPersistentStoreCoordinator,
        options: [AnyHashable: Any]
    ) throws {
        try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL,
            options: options
        )
    }
}
