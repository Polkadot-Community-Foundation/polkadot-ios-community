import Foundation
import Individuality
import SubstrateSdk

/// Releases chat allowances whose contact is gone, blocked or has no established chat;
/// every other established chat keeps renewing.
final class ChatAllowanceFilter {
    private let contactsStorageService: ContactsLocalStorageServicing
    private let statementSignerResolver: ChatStatementSignerResolving

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
        let neededAccounts = try Set(contacts.filter { !$0.isBlocked }.map { contact in
            try statementSignerResolver.statementSigner(for: contact.accountId).accountId
        })

        return chatRecords.filter { !neededAccounts.contains($0.accountId) }
    }
}
