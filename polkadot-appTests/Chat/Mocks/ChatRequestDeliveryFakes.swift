import Foundation
import IssueMonitoring
import MessageExchangeKit
import os
import StatementStore
import SubstrateSdk
@testable import polkadot_app

final class RecordingOutgoingChatRequestService: OutgoingChatRequestServicing, @unchecked Sendable {
    /// Failures thrown by the leading sends; later sends succeed.
    var failures: [Error] = []
    var encodedSize = 1_000
    var storedSigners: Set<AccountId> = []
    private let sent = OSAllocatedUnfairLock<[AccountId]>(initialState: [])

    var sentSigners: [AccountId] { sent.withLock { $0 } }

    func send(
        message _: Chat.RequestMessage,
        to _: MessageExchange.Peer,
        ownKeyId _: MessageExchange.Own,
        signer: StatementStoreSigning
    ) async throws {
        if !failures.isEmpty { throw failures.removeFirst() }
        sent.withLock { $0.append(signer.accountId) }
    }

    func encodedSize(
        of _: Chat.RequestMessage,
        to _: MessageExchange.Peer,
        ownKeyId _: MessageExchange.Own
    ) throws -> Int {
        encodedSize
    }

    func isStored(
        to _: MessageExchange.Peer,
        ownKeyId _: MessageExchange.Own,
        signedBy accountId: AccountId
    ) async throws -> Bool {
        storedSigners.contains(accountId)
    }
}

final class InMemoryChatRequestRenewalStore: ChatRequestRenewalStoring, @unchecked Sendable {
    private struct Writes {
        var periodUpdates: [(requestId: String, period: UInt32)] = []
        var failed: [String] = []
    }

    var candidates: [ChatRequestRenewalCandidate] = []
    private let writes = OSAllocatedUnfairLock(uncheckedState: Writes())

    var periodUpdates: [(requestId: String, period: UInt32)] { writes.withLock { $0.periodUpdates } }
    var failed: [String] { writes.withLock { $0.failed } }

    func renewalCandidates() async throws -> [ChatRequestRenewalCandidate] {
        candidates
    }

    func updateAnonymousPeriod(requestId: String, period: UInt32) async throws {
        writes.withLock { $0.periodUpdates.append((requestId, period)) }
    }

    func markFailed(requestId: String) async throws {
        writes.withLock { $0.failed.append(requestId) }
    }
}

final class StubDeliveryAccountResolver: ChatRequestDeliveryAccountResolving, @unchecked Sendable {
    let signer: ChatRequestDeliverySigner
    var statementSize = 10 * 1_024
    var error: Error?
    private(set) var resolvedCount = 0

    init(signer: ChatRequestDeliverySigner) {
        self.signer = signer
    }

    func maxStatementSize() async throws -> Int {
        statementSize
    }

    func resolveFirstDelivery(
        requestId _: String,
        session _: MessageExchange.SessionRequest
    ) async throws -> ChatRequestDeliverySigner {
        resolvedCount += 1
        if let error { throw error }
        return signer
    }
}

final class InMemoryChatRequestDeliveryStore: ChatRequestDeliveryStoring, @unchecked Sendable {
    var isAwaiting = true
    /// Stops awaiting after this many reads; nil keeps `isAwaiting` as is.
    var awaitingReadsLeft: Int?
    private(set) var delivered: [(requestId: String, anonymousPeriod: UInt32)] = []
    private(set) var failed: [String] = []

    func isAwaitingDelivery(requestId _: String) async throws -> Bool {
        if let left = awaitingReadsLeft {
            awaitingReadsLeft = left - 1
            return left > 0
        }
        return isAwaiting
    }

    func markDelivered(requestId: String, anonymousPeriod: UInt32) async throws {
        delivered.append((requestId, anonymousPeriod))
        isAwaiting = false
    }

    func markFailed(requestId: String) async throws {
        failed.append(requestId)
        isAwaiting = false
    }
}

extension ChatRequestDiagnostics {
    static var noop: Self {
        ChatRequestDiagnostics(logger: MockLogger(), issues: .make(reporter: NoopIssueReporter()))
    }
}
