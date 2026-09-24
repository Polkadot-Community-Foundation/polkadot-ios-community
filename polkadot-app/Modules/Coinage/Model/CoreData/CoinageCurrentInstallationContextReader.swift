import Coinage
import CoreData
import Foundation
import os

/// The current installation as the store itself names it: the one `CDCurrentInstallation` row, read on
/// the context of the row being mapped so the answer is consistent with that row.
///
/// The row never changes once created, so a found id is kept for the life of the reader. A missing row
/// is not cached: it appears once, when the first allocation or recovery creates it, and until then no
/// row can have come from another installation.
final class CoinageCurrentInstallationContextReader: @unchecked Sendable {
    private let cached = OSAllocatedUnfairLock<CoinageInstallationId?>(initialState: nil)

    func current(in context: NSManagedObjectContext) throws -> CoinageInstallationId? {
        if let known = cached.withLock({ $0 }) { return known }

        let request = NSFetchRequest<CDCurrentInstallation>(entityName: Self.entityName)
        request.fetchLimit = 1
        guard let row = try context.fetch(request).first else { return nil }
        guard let identifier = row.identifier else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDCurrentInstallation.identifier))
        }

        let installation = try CoinageInstallationId(hex: identifier)
        cached.withLock { $0 = installation }
        return installation
    }
}

extension CoinageCurrentInstallationContextReader {
    /// Whether `index` was allocated by an installation other than the one the row's store names as
    /// current. With no current row yet nothing has been recovered yet, so `false` is the truthful answer.
    func isRecovered(_ index: CoinageKeyIndex, of entity: NSManagedObject) throws -> Bool {
        guard let context = entity.managedObjectContext else {
            throw CoreDataMapperError.missingRequiredData(keyPath: "managedObjectContext")
        }
        guard let current = try current(in: context) else { return false }
        return index.installation != current
    }
}

private extension CoinageCurrentInstallationContextReader {
    static let entityName = "CDCurrentInstallation"
}
