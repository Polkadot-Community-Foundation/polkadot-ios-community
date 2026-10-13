import Foundation
import SubstrateSdk

public protocol AllowanceReleaseFiltering {
    /// The records whose allowances are no longer needed; the manager deletes them so they are never renewed.
    func recordsToRelease(from records: [AllowanceRecord]) async throws -> [AllowanceRecord]
}

public struct AccountsAllowanceFilter: AllowanceReleaseFiltering {
    private let accountIds: Set<AccountId>

    public init(accountIds: Set<AccountId>) {
        self.accountIds = accountIds
    }

    public func recordsToRelease(from records: [AllowanceRecord]) async throws -> [AllowanceRecord] {
        records.filter { accountIds.contains($0.accountId) }
    }
}
