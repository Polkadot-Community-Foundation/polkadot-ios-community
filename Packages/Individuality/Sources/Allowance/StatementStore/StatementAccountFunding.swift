import Foundation
import SubstrateSdk

public protocol StatementAccountFunding {
    /// Funds `accountId` for the current period unless it already has a slot; never takes another account's slot.
    func ensureFunded(accountId: AccountId, priority: AllowanceRecord.Priority) async throws
}
