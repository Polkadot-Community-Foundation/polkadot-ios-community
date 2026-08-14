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
            // 0.10.0 squashed UserDataModel 1...36 into UserDataModel41, so a store written by
            // any earlier build has no source model left in the bundle and Core Data cannot
            // infer a mapping. Nothing can migrate it, so drop it and start clean rather than
            // crashing on every launch.
            //
            // Neither keys nor funds live in this store: the wallet entropy is in the keychain
            // (and optionally iCloud, via Settings -> Backup), the username is Identity-pallet
            // state keyed by account id, and CoinKeypairFactory derives coin keys from the root
            // entropy along `//pps//coin`, so CoinageBackupRecoveryService re-derives coins and
            // vouchers by scanning the chain. What is lost is local-only state, chiefly chat
            // history — see the release notes for this build.
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

    /// True only when the store cannot be migrated because the model that wrote it is no longer
    /// shipped — as opposed to a transient failure (disk full, permissions, a locked file), where
    /// destroying the store would throw away recoverable user data.
    static func isUnmigratableStore(_ error: Error) -> Bool {
        let error = error as NSError

        guard error.domain == NSCocoaErrorDomain else {
            return false
        }

        return error.code == NSPersistentStoreIncompatibleVersionHashError
            || error.code == NSMigrationMissingSourceModelError
    }
}
