import Foundation
import StatementStore
import SubstrateSdk

/// Waits until `accountId` may submit statements, for example until its allowance is funded.
public protocol PeerSessionSubmissionGating: Sendable {
    func awaitSubmittable(accountId: AccountId) async throws
}

struct GatedStatementSubmitter: StatementStoreSubmitting {
    let base: StatementStoreSubmitting
    let accountId: AccountId
    let gate: PeerSessionSubmissionGating

    func submitStatement(with builder: StatementSubmitParametersBuilding) async throws {
        try await gate.awaitSubmittable(accountId: accountId)
        try await base.submitStatement(with: builder)
    }
}
