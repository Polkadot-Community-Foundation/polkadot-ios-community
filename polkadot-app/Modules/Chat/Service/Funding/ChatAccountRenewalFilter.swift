import Foundation
import FoundationExt
import Individuality
import os
import StatementStore
import SubstrateSdk

/// Lets a chat's statement account lapse once the chat is idle; other allowances always renew.
final class ChatAccountRenewalFilter: @unchecked Sendable {
    private let activityProvider: ChatActivityProviding
    private let peerAccounts: ChatPeerAccountsProviding
    private let signManager: StatementStoreSignerManaging
    private let dateProvider: DateProviding
    private let statementAccountByPeer = OSAllocatedUnfairLock<[AccountId: AccountId]>(initialState: [:])

    init(
        activityProvider: ChatActivityProviding,
        peerAccounts: ChatPeerAccountsProviding,
        signManager: StatementStoreSignerManaging,
        dateProvider: DateProviding
    ) {
        self.activityProvider = activityProvider
        self.peerAccounts = peerAccounts
        self.signManager = signManager
        self.dateProvider = dateProvider
    }
}

extension ChatAccountRenewalFilter: AllowanceRenewalFiltering {
    func renewable(_ records: [AllowanceRecord]) async throws -> [AllowanceRecord] {
        let now = await dateProvider.read()
        let activity = try await activityProvider.activity(since: now.addingTimeInterval(-Self.idleWindow))
        let peerByStatementAccount = try Dictionary(
            activity.peers.map { try (statementAccountId(for: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return records.filter { record in
            guard let peer = peerByStatementAccount[record.accountId] else {
                return true
            }

            return activity.activePeers.contains(peer)
        }
    }
}

private extension ChatAccountRenewalFilter {
    static let idleWindow: TimeInterval = 3 * 86_400

    // Derivation reads the mnemonic, so each peer's account is derived once.
    func statementAccountId(for peer: AccountId) throws -> AccountId {
        if let cached = statementAccountByPeer.withLock({ $0[peer] }) {
            return cached
        }

        let accountId = try signManager.makeSigner(for: peerAccounts.statementKeyId(for: peer)).accountId
        statementAccountByPeer.withLock { $0[peer] = accountId }
        return accountId
    }
}
