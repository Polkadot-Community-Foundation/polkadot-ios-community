@testable import polkadot_app
import Foundation
import Operation_iOS
import SubstrateSdk

final class MockLocalContactSearch: LocalContactSearching {
    var contacts: [Chat.Contact] = []

    // Recorded inputs
    var receivedUsernamePrefix: String?
    var receivedAccountId: AccountId?
    var didRequestAllContacts: Bool = false

    func searchContacts(usernamePrefix: String) -> AnyDataProviderRepository<Chat.Contact> {
        receivedUsernamePrefix = usernamePrefix
        return makeSeededRepository()
    }

    func contact(accountId: AccountId) -> AnyDataProviderRepository<Chat.Contact> {
        receivedAccountId = accountId
        return makeSeededRepository()
    }

    func allContacts() -> AnyDataProviderRepository<Chat.Contact> {
        didRequestAllContacts = true
        return makeSeededRepository()
    }

    private func makeSeededRepository() -> AnyDataProviderRepository<Chat.Contact> {
        let repository = InMemoryDataProviderRepository<Chat.Contact>()
        // Use a blocking operation queue to seed synchronously
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1
        let seedOp = repository.replaceOperation { self.contacts }
        operationQueue.addOperation(seedOp)
        operationQueue.waitUntilAllOperationsAreFinished()
        return AnyDataProviderRepository(repository)
    }
}
