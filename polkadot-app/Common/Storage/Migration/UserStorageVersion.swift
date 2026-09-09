import Foundation

enum UserStorageVersion: String, CaseIterable {
    /// FORK DELTA. Upstream's 0.10.0 squash (a6ce195) deleted models 1...36 and restarted this
    /// enum at 41, but every store installed from a PCF build made before that squash is still
    /// at 36.
    ///
    /// Without this case a v36 store matches nothing in `allCases`, so
    /// `StorageMigrating+CheckVersion.swift` reports `nil` for the compatible version,
    /// `requiresMigration()` returns true, and `performMigration()` asks Core Data to open the
    /// store against the v42 model with no v36 source model in the bundle. `addPersistentStore`
    /// throws `NSMigrationMissingSourceModelError` and `UserStorageMigrator.performMigration`
    /// ends in `fatalError` — a crash on every launch, unrecoverable without deleting the app.
    ///
    /// Restoring the model is what makes the migration possible; Core Data finds the SOURCE model
    /// by hash-scanning the bundle, so `performMigration()` never consults `nextVersion()`. The
    /// case is what makes `requiresMigration()` recognise the store in the first place.
    ///
    /// The case and `UserDataModel36.xcdatamodel` are hard-coupled in both directions:
    /// `createManagedObjectModel` calls `fatalError` when the .mom is missing, so adding the case
    /// without the model turns every launch into a crash. Neither may land without the other.
    ///
    /// Declaration order matters: `allCases.first { ... }` takes the first hash-compatible match,
    /// so versions must stay ascending.
    case version36 = "UserDataModel36"
    case version41 = "UserDataModel41"
    case version42 = "UserDataModel42"
    case version43 = "UserDataModel43"
    case version44 = "UserDataModel44"
    case version45 = "UserDataModel45"

    func nextVersion() -> UserStorageVersion? {
        switch self {
        case .version36:
            .version41
        case .version41:
            .version42
        case .version42:
            .version43
        case .version43:
            .version44
        case .version44:
            .version45
        case .version45:
            nil
        }
    }
}
