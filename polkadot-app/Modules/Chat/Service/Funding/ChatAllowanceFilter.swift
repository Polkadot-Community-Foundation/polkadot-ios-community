import Foundation
import FoundationExt
import Individuality
import os
import StatementStore
import SubstrateSdk

/// Releases chat allowances that are no longer needed: idle chats, removed contacts and blocked contacts.
final class ChatAllowanceFilter: @unchecked Sendable {
    private let activityProvider: ChatActivityProviding
    private let statementAccountResolver: ChatStatementAccountResolving
    private let dateProvider: DateProviding
    private let statementAccountByPeer = OSAllocatedUnfairLock<[AccountId: AccountId]>(initialState: [:])

    init(
        activityProvider: ChatActivityProviding,
        statementAccountResolver: ChatStatementAccountResolving,
        dateProvider: DateProviding
    ) {
        self.activityProvider = activityProvider
        self.statementAccountResolver = statementAccountResolver
        self.dateProvider = dateProvider
    }
}

extension ChatAllowanceFilter: AllowanceReleaseFiltering {
    func recordsToRelease(from records: [AllowanceRecord]) async throws -> [AllowanceRecord] {
        let chatRecords = records.filter { $0.domain == .chat }

        guard !chatRecords.isEmpty else { return [] }

        let now = await dateProvider.read()
        let activePeers = try await activityProvider.activePeers(since: now.addingTimeInterval(-Self.idleWindow))
        let neededAccounts = try Set(activePeers.map(statementAccountId(for:)))

        return chatRecords.filter { !neededAccounts.contains($0.accountId) }
    }
}

private extension ChatAllowanceFilter {
    static let idleWindow: TimeInterval = 3 * 86_400

    // Derivation reads the mnemonic, so each peer's account is derived once.
    func statementAccountId(for peer: AccountId) throws -> AccountId {
        if let cached = statementAccountByPeer.withLock({ $0[peer] }) {
            return cached
        }

        let accountId = try statementAccountResolver.statementAccountId(for: peer)
        statementAccountByPeer.withLock { $0[peer] = accountId }
        return accountId
    }
}
