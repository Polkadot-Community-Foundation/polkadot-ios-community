import CoreData
@testable import polkadot_app
import XCTest

/// Covers the upgrade path from a build that shipped an older `UserDataModel`.
///
/// 0.10.0 dropped every model version except `UserDataModel41`, while our released builds write
/// `UserDataModel36`. Core Data cannot infer a mapping without the source model in the bundle, so
/// `addPersistentStore` fails and — before the fix these tests pin — `performMigration`'s
/// `fatalError` turned every existing install into a crash loop on launch.
final class UserStorageMigratorTests: XCTestCase {
    private var directory: URL!

    private var storeURL: URL {
        directory.appendingPathComponent("UserDataModel.sqlite")
    }

    override func setUpWithError() throws {
        try super.setUpWithError()

        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil

        try super.tearDownWithError()
    }

    // MARK: - The regression

    /// A store written by a model that is no longer shipped must be recreated, not trapped on.
    func testRecreatesStoreWrittenByAnUnshippedModel() throws {
        try makeLegacyStore()

        makeMigrator().performMigration()

        // Reaching here at all is most of the point: the pre-fix implementation called
        // `fatalError`, which takes the whole test runner down with it.
        let coordinator = try openStoreWithCurrentModel()

        XCTAssertEqual(
            coordinator.persistentStores.count,
            1,
            "the recreated store should open against the current model"
        )
    }

    /// The recreated store has to be usable, not merely openable.
    func testRecreatedStoreAcceptsWrites() throws {
        try makeLegacyStore()

        makeMigrator().performMigration()

        let coordinator = try openStoreWithCurrentModel()
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        try context.performAndWait {
            let object = NSEntityDescription.insertNewObject(
                forEntityName: "CDKeystoreIntegrity",
                into: context
            )
            object.setValue("probe", forKey: "keyTag")
            object.setValue(Data([0x01]), forKey: "integrityKey")

            try context.save()

            let request = NSFetchRequest<NSManagedObject>(entityName: "CDKeystoreIntegrity")
            XCTAssertEqual(try context.fetch(request).count, 1)
        }
    }

    // MARK: - The thing that must NOT happen

    /// A store already on the current model must be left alone. If `requiresMigration` ever
    /// returns `true` here, the recreate path would run against healthy data and delete it.
    func testStoreOnCurrentModelIsNotMigrated() throws {
        let coordinator = try openStoreWithCurrentModel()
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        try context.performAndWait {
            let object = NSEntityDescription.insertNewObject(
                forEntityName: "CDKeystoreIntegrity",
                into: context
            )
            object.setValue("keep-me", forKey: "keyTag")
            object.setValue(Data([0x02]), forKey: "integrityKey")

            try context.save()
        }

        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }

        XCTAssertFalse(
            makeMigrator().requiresMigration(),
            "a store already on the current model must not be migrated, let alone recreated"
        )
    }

    // MARK: - Error classification

    /// Widening this predicate is how the fix turns into data loss: any error that is not
    /// "the model that wrote this store is gone" must keep hitting `fatalError` instead of
    /// destroying a store that a retry could have opened.
    func testOnlyMissingSourceModelErrorsAreTreatedAsUnmigratable() {
        let unmigratable = [
            NSPersistentStoreIncompatibleVersionHashError,
            NSMigrationMissingSourceModelError
        ]

        for code in unmigratable {
            XCTAssertTrue(
                UserStorageMigrator.isUnmigratableStore(
                    NSError(domain: NSCocoaErrorDomain, code: code)
                ),
                "code \(code) should be recoverable by recreating the store"
            )
        }

        let transient = [
            NSFileWriteOutOfSpaceError,
            NSFileWriteNoPermissionError,
            NSPersistentStoreOpenError,
            NSMigrationError
        ]

        for code in transient {
            XCTAssertFalse(
                UserStorageMigrator.isUnmigratableStore(
                    NSError(domain: NSCocoaErrorDomain, code: code)
                ),
                "code \(code) may be transient — destroying the store would lose real user data"
            )
        }

        XCTAssertFalse(
            UserStorageMigrator.isUnmigratableStore(
                NSError(domain: NSPOSIXErrorDomain, code: NSPersistentStoreIncompatibleVersionHashError)
            ),
            "the code is only meaningful inside NSCocoaErrorDomain"
        )
    }
}

// MARK: - Helpers

private extension UserStorageMigratorTests {
    var options: [AnyHashable: Any] {
        [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true,
            NSPersistentHistoryTrackingKey: true
        ]
    }

    func makeMigrator() -> UserStorageMigrator {
        UserStorageMigrator(
            storeURL: storeURL,
            modelDirectory: UserStorageParams.modelDirectory,
            model: UserStorageParams.modelVersion,
            fileManager: FileManager.default
        )
    }

    func currentModel() throws -> NSManagedObjectModel {
        let name = UserStorageParams.modelVersion.rawValue
        let directory = UserStorageParams.modelDirectory

        let url = Bundle.main.url(forResource: name, withExtension: "omo", subdirectory: directory)
            ?? Bundle.main.url(forResource: name, withExtension: "mom", subdirectory: directory)

        let modelURL = try XCTUnwrap(url, "\(name) is missing from \(directory) in the app bundle")

        return try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
    }

    func openStoreWithCurrentModel() throws -> NSPersistentStoreCoordinator {
        let coordinator = try NSPersistentStoreCoordinator(managedObjectModel: currentModel())

        try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL,
            options: options
        )

        return coordinator
    }

    /// Writes a store using a model that is deliberately absent from every bundle, which is what
    /// a `UserDataModel36` store looks like to a build that only ships `UserDataModel41`.
    /// Building it in code rather than vendoring the retired `.xcdatamodel` keeps the app bundle
    /// unchanged — shipping the old model again would itself alter migration behaviour.
    func makeLegacyStore() throws {
        let entity = NSEntityDescription()
        entity.name = "CDRetiredEntity"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let attribute = NSAttributeDescription()
        attribute.name = "identifier"
        attribute.attributeType = .stringAttributeType
        attribute.isOptional = false
        entity.properties = [attribute]

        let model = NSManagedObjectModel()
        model.entities = [entity]

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)

        try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL,
            options: options
        )

        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        try context.performAndWait {
            let object = NSEntityDescription.insertNewObject(
                forEntityName: "CDRetiredEntity",
                into: context
            )
            object.setValue(UUID().uuidString, forKey: "identifier")

            try context.save()
        }

        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }
    }
}
