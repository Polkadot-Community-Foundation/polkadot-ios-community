import Foundation
import Testing
@testable import polkadot_app

struct BlockUserServiceTests {
    private let facade = UserDataStorageTestFacade()
    private let cleanupService = SpyAllowanceCleanupService()
    private let peerAccountId = Data(repeating: 0x01, count: 32)

    @Test func blockingCleansUpAllowances() async throws {
        try await insertContact()
        try await makeService().blockUser(accountId: peerAccountId)

        #expect(cleanupService.cleanupCount == 1)
    }

    @Test func unblockingLeavesAllowancesToOnDemandFunding() async throws {
        try await insertContact()
        try await makeService().unblockUser(accountId: peerAccountId)

        #expect(cleanupService.cleanupCount == 0)
    }
}

private extension BlockUserServiceTests {
    func makeService() -> BlockUserService {
        BlockUserService(allowanceCleanupService: cleanupService, storageFacade: facade)
    }

    func insertContact() async throws {
        try await facade.databaseService.performWrite { [peerAccountId] context in
            let contact = CDChatContact(context: context)
            contact.identifier = peerAccountId.toHex()
            contact.username = "peer"
            contact.publicKey = Data(repeating: 0x02, count: 32)
            contact.ownSignKeyId = "//wallet//main"
        }
    }
}
