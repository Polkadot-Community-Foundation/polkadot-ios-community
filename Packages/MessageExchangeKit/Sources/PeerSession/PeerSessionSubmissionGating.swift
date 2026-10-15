import Foundation
import StatementStore

/// Picks the account that signs a session's next statement, waiting until it may submit (for example, until funded).
public protocol PeerSessionSubmissionGating: Sendable {
    func signer(for request: MessageExchange.SessionRequest) async throws -> StatementStoreSigning
}

/// Signs and submits a session's statements; channels hand over fields only.
protocol PeerSessionStatementSubmitting {
    func submit(_ statement: UnsignedStatement) async throws
}

struct SigningStatementSubmitter: PeerSessionStatementSubmitting {
    let signer: StatementStoreSigning
    let base: StatementStoreSubmitting

    func submit(_ statement: UnsignedStatement) async throws {
        try await base.submitStatement(with: statement.signed(by: signer))
    }
}

struct GatedStatementSubmitter: PeerSessionStatementSubmitting {
    let base: StatementStoreSubmitting
    let request: MessageExchange.SessionRequest
    let gate: PeerSessionSubmissionGating

    func submit(_ statement: UnsignedStatement) async throws {
        let signer = try await gate.signer(for: request)
        try await base.submitStatement(with: statement.signed(by: signer))
    }
}
