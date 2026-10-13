import Foundation
import SubstrateSdk

public protocol StatementAccountFunding {
    /// Funds `accountId` for the current period unless it already has a slot.
    func ensureFunded(
        accountId: AccountId,
        priority: AllowanceRecord.Priority,
        domain: AllowanceRecord.Domain
    ) async throws
}
