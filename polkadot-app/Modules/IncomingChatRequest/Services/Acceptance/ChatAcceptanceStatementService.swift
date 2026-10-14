import Foundation
import MessageExchangeKit
import StatementStore
import SubstrateSdk

protocol ChatAcceptanceStatementServicing {
    func send(_ candidate: ChatAcceptanceCandidate, signer: StatementStoreSigning) async throws
    func isStored(_ candidate: ChatAcceptanceCandidate, signedBy accountId: AccountId) async throws -> Bool
}

/// Publishes acceptances on the identity route, outside the chat session.
final class ChatAcceptanceStatementService {
    private let requestFactory: IdentityRouteRequestMaking
    private let connection: StatementStoreConnecting

    init(requestFactory: IdentityRouteRequestMaking, connection: StatementStoreConnecting) {
        self.requestFactory = requestFactory
        self.connection = connection
    }
}

extension ChatAcceptanceStatementService: ChatAcceptanceStatementServicing {
    func send(_ candidate: ChatAcceptanceCandidate, signer: StatementStoreSigning) async throws {
        guard let remoteMessage = candidate.message.toRemote() else {
            throw ChatAcceptanceStatementServiceError.notRemote
        }

        let statement = try requestFactory.makeRequestStatement(
            for: candidate.session,
            requestId: candidate.message.messageId,
            message: Chat.OpaqueMessage(remoteMessage: remoteMessage),
            signer: signer
        )

        try await connection.submitStatement(with: statement)
    }

    // The acceptor publishes nothing else on this topic, so any statement from the signer is the acceptance.
    func isStored(_ candidate: ChatAcceptanceCandidate, signedBy accountId: AccountId) async throws -> Bool {
        let topic = try requestFactory.requestTopic(for: candidate.session)
        let statements = try await connection.fetchStatements(with: .matchAll([topic]))

        return try statements.contains { data in
            let statement = try Statement(scaleDecoder: ScaleDecoder(data: data))

            guard case let .sr25519(_, signer) = statement.getProof() else { return false }

            return signer == accountId
        }
    }
}

enum ChatAcceptanceStatementServiceError: Error {
    case notRemote
}
