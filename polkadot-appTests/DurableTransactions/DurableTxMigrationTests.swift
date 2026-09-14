import CoreData
import Foundation
import Testing

@testable import polkadot_app

/// UserDataModel 47 → 48: `CDCoinageTxEntry` becomes the domain-neutral `CDDurableTx` with a `domainId`,
/// and coinage's input/output rows keep pointing at it. A store with rows in it must come through the
/// lightweight migration with the same ids, statuses and asset links.
@Suite("Durable transaction store migration", .serialized)
struct DurableTxMigrationTests {
    private static let entryId = UUID().uuidString
    private static let coinKeyHex = "0x0102"

    @Test("The current model is 48 and follows 47")
    func versionChain() {
        #expect(UserStorageParams.modelVersion == .version48)
        #expect(UserStorageVersion.version47.nextVersion() == .version48)
        #expect(UserStorageVersion.version48.nextVersion() == nil)
    }

    @Test("A 47 store with a coinage entry migrates to 48 keeping the row, its id and its asset links")
    func migratesEntryWithAssets() throws {
        let storeURL = try makeStore47WithRows()
        defer { removeStore(at: storeURL) }

        let migrator = UserStorageMigrator(
            storeURL: storeURL,
            modelDirectory: UserStorageParams.modelDirectory,
            model: .version47,
            fileManager: .default
        )
        #expect(migrator.requiresMigration())

        migrator.performMigration()

        #expect(!migrator.requiresMigration())

        let context = try open(storeURL, model: model(.version48))
        let request = NSFetchRequest<NSManagedObject>(entityName: "CDDurableTx")
        let rows = try context.fetch(request)
        try #require(rows.count == 1)

        let row = rows[0]
        #expect(row.value(forKey: "identifier") as? String == Self.entryId)
        #expect(row.value(forKey: "domainId") as? String == "coinage")
        #expect(row.value(forKey: "status") as? Int16 == 1)
        #expect(row.value(forKey: "sequence") as? Int64 == 7)

        let inputs = try #require(row.value(forKey: "inputs") as? Set<NSManagedObject>)
        #expect(inputs.count == 1)
        let coin = try #require(inputs.first?.value(forKey: "coin") as? NSManagedObject)
        #expect(coin.value(forKey: "publicKey") as? String == Self.coinKeyHex)
    }
}

private extension DurableTxMigrationTests {
    func model(_ version: UserStorageVersion) throws -> NSManagedObjectModel {
        let bundle = Bundle.main
        let url = bundle.url(
            forResource: version.rawValue,
            withExtension: "omo",
            subdirectory: UserStorageParams.modelDirectory
        )
            ?? bundle.url(
                forResource: version.rawValue,
                withExtension: "mom",
                subdirectory: UserStorageParams.modelDirectory
            )
        let modelURL = try #require(url)
        return try #require(NSManagedObjectModel(contentsOf: modelURL))
    }

    /// Opens (or creates) the SQLite store with `model`, with the same options the live store uses.
    func open(_ storeURL: URL, model: NSManagedObjectModel) throws -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL,
            options: [NSPersistentHistoryTrackingKey: true]
        )
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }

    /// A 47 store holding one coin, one entry consuming it (status pendingSuccess, sequence 7) and the
    /// input row linking the two.
    func makeStore47WithRows() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("durable-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("UserDataModel_v2.sqlite")

        let context = try open(storeURL, model: model(.version47))

        let coin = NSEntityDescription.insertNewObject(forEntityName: "CDCoin", into: context)
        coin.setValue("coin:0", forKey: "identifier")
        coin.setValue(false, forKey: "isOnchain")
        coin.setValue(Self.coinKeyHex, forKey: "publicKey")

        let entry = NSEntityDescription.insertNewObject(forEntityName: "CDCoinageTxEntry", into: context)
        entry.setValue(Self.entryId, forKey: "identifier")
        entry.setValue(Int64(7), forKey: "sequence")
        entry.setValue(Int16(1), forKey: "status")
        entry.setValue(Date(), forKey: "createdAt")
        entry.setValue(Int32(64), forKey: "mortality")
        entry.setValue("0xaa", forKey: "checkpointHash")
        entry.setValue(NSNumber(value: 100), forKey: "checkpointNumber")
        entry.setValue("0xbb", forKey: "txHash")

        let input = NSEntityDescription.insertNewObject(forEntityName: "CDCoinageTxInput", into: context)
        input.setValue(entry, forKey: "entry")
        input.setValue(coin, forKey: "coin")

        try context.save()
        if let store = context.persistentStoreCoordinator?.persistentStores.first {
            try context.persistentStoreCoordinator?.remove(store)
        }
        return storeURL
    }

    func removeStore(at storeURL: URL) {
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
    }
}
