import Foundation
import Individuality
import os
import SubstrateSdk

/// Releases chat allowances whose contact is gone or has no established chat; every established chat keeps renewing.
final class ChatAllowanceFilter: @unchecked Sendable {
    private let contactsStorageService: ContactsLocalStorageServicing
    private let statementSignerResolver: ChatStatementSignerResolving
    private let statementAccountByPeer = OSAllocatedUnfairLock<[AccountId: AccountId]>(initialState: [:])

    init(
        contactsStorageService: ContactsLocalStorageServicing,
        statementSignerResolver: ChatStatementSignerResolving
    ) {
        self.contactsStorageService = contactsStorageService
        self.statementSignerResolver = statementSignerResolver
    }
}

extension ChatAllowanceFilter: AllowanceReleaseFiltering {
    func recordsToRelease(from records: [AllowanceRecord]) async throws -> [AllowanceRecord] {
        let chatRecords = records.filter { $0.domain == .chat }

        guard !chatRecords.isEmpty else { return [] }

        let contacts = try await contactsStorageService.getEstablishedContacts().asyncExecute()
        let neededAccounts = try Set(contacts.map { try statementAccountId(for: $0.accountId) })

        return chatRecords.filter { !neededAccounts.contains($0.accountId) }
    }
}

private extension ChatAllowanceFilter {
    // Derivation reads the mnemonic, so each peer's account is derived once.
    func statementAccountId(for peer: AccountId) throws -> AccountId {
        if let cached = statementAccountByPeer.withLock({ $0[peer] }) {
            return cached
        }

        let accountId = try statementSignerResolver.statementSigner(for: peer).accountId
        statementAccountByPeer.withLock { $0[peer] = accountId }
        return accountId
    }
}
