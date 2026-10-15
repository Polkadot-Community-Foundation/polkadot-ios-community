import CoreData
@testable import polkadot_app
import XCTest

/// Migrates a store written by `UserDataModel36`, the model older installs carry, to the current
/// model (`UserStorageParams.modelVersion`). Only running it shows whether Core Data can infer the
/// mapping. If it fails, the delta needs an explicit mapping; do not remove the v36 model or case.
final class UserStorageMigrationV36Tests: XCTestCase {
    private var directory: URL!

    private var storeURL: URL {
        directory.appendingPathComponent(UserStorageParams.databaseName)
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

    // MARK: - The v36 model

    /// The `version36` case and `UserDataModel36.xcdatamodel` must ship together: the case without
    /// the model traps at launch.
    func testVersion36ModelIsShippedInTheAppBundle() throws {
        let name = UserStorageVersion.version36.rawValue
        let directory = UserStorageParams.modelDirectory

        let url = Bundle.main.url(forResource: name, withExtension: "omo", subdirectory: directory)
            ?? Bundle.main.url(forResource: name, withExtension: "mom", subdirectory: directory)

        let modelURL = try XCTUnwrap(
            url,
            "\(name) is missing from \(directory); a v36 store has no source model without it."
        )

        XCTAssertNotNil(NSManagedObjectModel(contentsOf: modelURL))
    }

    /// Ascending declaration order is load-bearing: `checkIfMigrationNeeded` takes the *first*
    /// hash-compatible match out of `allCases`.
    func testVersionsAreDeclaredAscending() {
        // The destination moves with each model bump, so it is read from the declaration: v36 comes
        // first, the order is strictly ascending, and the last case is the one the app opens.
        let cases = UserStorageVersion.allCases
        let numbers = cases.map { Int($0.rawValue.replacingOccurrences(of: "UserDataModel", with: "")) ?? -1 }
        XCTAssertEqual(cases.first, .version36, "the v36 case must be matched before any newer model")
        XCTAssertEqual(
            numbers,
            numbers.sorted(),
            "allCases order decides which model a store is matched against, so it must stay ascending"
        )
        XCTAssertFalse(numbers.contains(-1), "every case must be named UserDataModel<n>")
        XCTAssertEqual(
            UserStorageParams.modelVersion,
            cases.last,
            "the app must open stores with the newest declared model"
        )
    }

    // MARK: - The migration

    func testVersion36StoreIsRecognisedAsNeedingMigration() throws {
        try makeVersion36Store()

        XCTAssertTrue(
            makeMigrator().requiresMigration(),
            "a v36 store must be recognised as behind the current destination"
        )
    }

    /// The load-bearing test. Writes a row under the real v36 model, migrates, and reads it back
    /// under v42.
    ///
    /// `CDProduct` is identical in `UserDataModel36` and the current model, so a value that does not
    /// survive means the migration went wrong, not the entity.
    func testVersion36StoreMigratesPreservingData() throws {
        let identifier = "v36-survivor-\(UUID().uuidString)"
        let name = "survivor-name"

        try makeVersion36Store(identifier: identifier, name: name)

        // Reaching the next line at all is part of the assertion: performMigration() calls
        // fatalError on failure, which takes the whole test runner down rather than failing a test.
        makeMigrator().performMigration()

        let coordinator = try openStore(with: UserStorageParams.modelVersion)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CDProduct")
            request.predicate = NSPredicate(format: "identifier == %@", identifier)

            let results = try context.fetch(request)

            XCTAssertEqual(
                results.count,
                1,
                "the row written under v36 must survive the migration to v42"
            )
            XCTAssertEqual(results.first?.value(forKey: "name") as? String, name)
        }
    }

    /// A migration that leaves the store still behind would loop on every launch.
    func testMigratedStoreNoLongerRequiresMigration() throws {
        try makeVersion36Store()

        makeMigrator().performMigration()

        XCTAssertFalse(
            makeMigrator().requiresMigration(),
            "after migrating, the store must be compatible with the destination model"
        )
    }

    /// Running the migrator twice must be a no-op, not a second migration attempt.
    func testMigrationIsIdempotent() throws {
        let identifier = "idempotent-\(UUID().uuidString)"

        try makeVersion36Store(identifier: identifier)

        makeMigrator().performMigration()
        makeMigrator().performMigration()

        let coordinator = try openStore(with: UserStorageParams.modelVersion)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CDProduct")
            request.predicate = NSPredicate(format: "identifier == %@", identifier)

            XCTAssertEqual(try context.fetch(request).count, 1)
        }
    }
}

// MARK: - Helpers

private extension UserStorageMigrationV36Tests {
    /// Mirrors `UserStorageMigrator.performMigration`'s options exactly. Persistent history
    /// tracking is enabled on the live store, and opening without it makes Core Data treat the
    /// store as read-only — the migration then fails with SQLite's misleading
    /// "attempt to write a readonly database".
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

    func model(for version: UserStorageVersion) throws -> NSManagedObjectModel {
        let directory = UserStorageParams.modelDirectory
        let name = version.rawValue

        let url = Bundle.main.url(forResource: name, withExtension: "omo", subdirectory: directory)
            ?? Bundle.main.url(forResource: name, withExtension: "mom", subdirectory: directory)

        let modelURL = try XCTUnwrap(url, "\(name) is missing from \(directory) in the app bundle")

        return try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
    }

    func openStore(with version: UserStorageVersion) throws -> NSPersistentStoreCoordinator {
        let coordinator = try NSPersistentStoreCoordinator(managedObjectModel: model(for: version))

        try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL,
            options: options
        )

        return coordinator
    }

    /// Writes a store using the shipped `UserDataModel36`, as an older install has on disk.
    func makeVersion36Store(
        identifier: String = "seed",
        name: String = "seed-name"
    ) throws {
        let coordinator = try openStore(with: .version36)

        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        try context.performAndWait {
            let object = NSEntityDescription.insertNewObject(
                forEntityName: "CDProduct",
                into: context
            )
            object.setValue(identifier, forKey: "identifier")
            object.setValue(name, forKey: "name")

            try context.save()
        }

        // Close the store so the migrator opens it cold, exactly as a fresh launch would.
        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }
    }
}
