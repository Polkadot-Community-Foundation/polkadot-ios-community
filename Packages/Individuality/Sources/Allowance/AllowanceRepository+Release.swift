import Foundation
import Operation_iOS

extension AnyDataProviderRepository where Model == AllowanceRecord {
    func releaseRecords(with filter: AllowanceReleaseFiltering) async throws {
        let records = try await fetchAllOperation(with: RepositoryFetchOptions()).asyncExecute()
        let released = try await filter.recordsToRelease(from: records)

        guard !released.isEmpty else { return }

        try await saveOperation({ [] }, { released.map(\.identifier) }).asyncExecute()
    }
}
