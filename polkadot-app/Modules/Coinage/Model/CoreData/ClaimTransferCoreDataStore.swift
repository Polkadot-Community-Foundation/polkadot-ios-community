import CoreData
import Foundation
import Operation_iOS

/// CoreData-backed ``ClaimTransferStoring``: one `CDClaimTransfer` row per incoming coinage message.
///
/// The read and the insert run as one block on the store's single context, so concurrent first callers
/// all get the anchor the block created — the same shape as
/// ``CoinageCurrentInstallationCoreDataRepository``.
final class ClaimTransferCoreDataStore: ClaimTransferStoring, @unchecked Sendable {
    private let databaseService: CoreDataServiceProtocol
    private let dateProvider: @Sendable () -> Date

    init(storageFacade: StorageFacadeProtocol, dateProvider: @escaping @Sendable () -> Date = { Date() }) {
        databaseService = storageFacade.databaseService
        self.dateProvider = dateProvider
    }

    func firstAttempt(for messageId: String) async throws -> Date {
        let now = dateProvider()

        return try await databaseService.performWrite { context in
            let request = NSFetchRequest<CDClaimTransfer>(entityName: Self.entityName)
            request.predicate = NSPredicate(format: "messageId == %@", messageId)
            request.fetchLimit = 1

            if let row = try context.fetch(request).first {
                return try Self.firstAttemptAt(of: row)
            }

            let row = try context.insertNew(CDClaimTransfer.self)
            row.messageId = messageId
            row.firstAttemptAt = now
            return now
        }
    }
}

private extension ClaimTransferCoreDataStore {
    static let entityName = "CDClaimTransfer"

    static func firstAttemptAt(of row: CDClaimTransfer) throws -> Date {
        guard let firstAttemptAt = row.firstAttemptAt else {
            throw CoreDataMapperError.missingRequiredData(keyPath: #keyPath(CDClaimTransfer.firstAttemptAt))
        }
        return firstAttemptAt
    }
}
