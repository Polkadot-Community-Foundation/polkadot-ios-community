import CoreData
@testable import polkadot_app
import XCTest

/// Executes the upgrade path that every existing PCF install has to survive: a store written by
/// `UserDataModel36` opening against the current model (`UserStorageParams.modelVersion`).
///
/// Upstream's 0.10.0 squash (`a6ce195`) deleted models 1...36 and restarted the version enum at 41,
/// but every PCF build shipped before that squash wrote a **v36** store. Without
/// `UserDataModel36.xcdatamodel` in the bundle Core Data has no source model to migrate from,
/// `addPersistentStore` throws `NSMigrationMissingSourceModelError`, and
/// `UserStorageMigrator.performMigration` ends in `fatalError` — a crash on every launch, with no
/// way to reach Settings -> Backup to export the recovery phrase first.
///
/// Restoring the model is what makes the migration *possible*. Whether Core Data can actually
/// **infer** a lightweight mapping from v36 to v42 is not something source review can establish —
/// it is decided at runtime by Core Data's inference engine, against the real compiled models. That
/// is precisely what these tests run, and it is the reason they exist: before this file, the
/// fork's central claim about the v36 upgrade path had never been executed anywhere.
///
/// If `testVersion36StoreMigratesPreservingData` fails, do **not** "fix" it by deleting the v36
/// model or the `version36` enum case. A failure here means the v36 -> v42 delta is not
/// lightweight-inferable and needs an explicit `NSEntityMigrationPolicy` (or a staged v36 -> v41
/// -> v42 migration), which is a real piece of work and not a test problem.
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

    // MARK: - The fork delta itself

    /// The `version36` enum case and `UserDataModel36.xcdatamodel` are hard-coupled in both
    /// directions: `createManagedObjectModel` traps when the .mom is missing, so the case without
    /// the model turns every launch into a crash. A future upstream sync that drops the model
    /// while keeping the case would be caught here rather than in the field.
    func testVersion36ModelIsShippedInTheAppBundle() throws {
        let name = UserStorageVersion.version36.rawValue
        let directory = UserStorageParams.modelDirectory

        let url = Bundle.main.url(forResource: name, withExtension: "omo", subdirectory: directory)
            ?? Bundle.main.url(forResource: name, withExtension: "mom", subdirectory: directory)

        let modelURL = try XCTUnwrap(
            url,
            "\(name) is missing from \(directory). The fork restores it precisely so a v36 store "
                + "has a source model; without it every pre-squash install crashes on launch."
        )

        XCTAssertNotNil(NSManagedObjectModel(contentsOf: modelURL))
    }

    /// Ascending declaration order is load-bearing: `checkIfMigrationNeeded` takes the *first*
    /// hash-compatible match out of `allCases`.
    func testVersionsAreDeclaredAscending() {
        // The destination moves with every upstream model bump (v42 -> v45 so far), so derive it
        // from the app's own declaration instead of pinning a literal. What must hold: the shipped
        // v36 model is matched FIRST, the declared order is strictly ascending by model number, and
        // the last declared version is the one the app opens stores with.
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
    /// `CDKeystoreIntegrity` is the fixture on purpose: its definition is byte-identical in
    /// `UserDataModel36` and the current model, so a value that fails to survive indicates the
    /// migration itself went wrong rather than an intentional schema change to that entity.
    func testVersion36StoreMigratesPreservingData() throws {
        let keyTag = "v36-survivor-\(UUID().uuidString)"
        let integrityKey = Data([0x01, 0x02, 0x03, 0x04])

        try makeVersion36Store(keyTag: keyTag, integrityKey: integrityKey)

        // Reaching the next line at all is part of the assertion: performMigration() calls
        // fatalError on failure, which takes the whole test runner down rather than failing a test.
        makeMigrator().performMigration()

        let coordinator = try openStore(with: UserStorageParams.modelVersion)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CDKeystoreIntegrity")
            request.predicate = NSPredicate(format: "keyTag == %@", keyTag)

            let results = try context.fetch(request)

            XCTAssertEqual(
                results.count,
                1,
                "the row written under v36 must survive the migration to v42"
            )
            XCTAssertEqual(results.first?.value(forKey: "integrityKey") as? Data, integrityKey)
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
        let keyTag = "idempotent-\(UUID().uuidString)"

        try makeVersion36Store(keyTag: keyTag)

        makeMigrator().performMigration()
        makeMigrator().performMigration()

        let coordinator = try openStore(with: UserStorageParams.modelVersion)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CDKeystoreIntegrity")
            request.predicate = NSPredicate(format: "keyTag == %@", keyTag)

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

    /// Writes a store using the **real** shipped `UserDataModel36`, which is what an install from
    /// any pre-squash PCF build looks like on disk.
    func makeVersion36Store(
        keyTag: String = "seed",
        integrityKey: Data = Data([0xAA])
    ) throws {
        let coordinator = try openStore(with: .version36)

        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        try context.performAndWait {
            let object = NSEntityDescription.insertNewObject(
                forEntityName: "CDKeystoreIntegrity",
                into: context
            )
            object.setValue(keyTag, forKey: "keyTag")
            object.setValue(integrityKey, forKey: "integrityKey")

            try context.save()
        }

        // Close the store so the migrator opens it cold, exactly as a fresh launch would.
        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }
    }
}
