import Foundation
import Individuality
import MessageExchangeKit
import Testing
@testable import polkadot_app

struct ChatRequestDeliveryAccountResolverTests {
    private let requestId = "request"
    private let allocator = StubNotificationAllocator()
    private let signerManager = ChatSignerManager(entropyManager: FixedRootEntropyManager())
    private let fallback = FakeIdentitySigningFallback(signer: StubStatementSigner(accountId: Data(
        repeating: 0x0C,
        count: 32
    )))
    private let session = MessageExchange.SessionRequest(
        own: .init(signKeyId: "//wallet//main", encryptionKeyId: "", pin: nil),
        peer: .init(
            accountId: Data(repeating: 0x0A, count: 32),
            publicKey: Data(repeating: 1, count: 32),
            pin: nil,
            devices: []
        )
    )

    @Test func signsWithPeriodAccountOnceItsSlotIsClaimed() async throws {
        let expected = try signerManager.makeChatRequestSigner(for: requestId, period: allocator.period)

        let resolved = try await makeResolver().resolveFirstDelivery(requestId: requestId, session: session)

        #expect(resolved.period == allocator.period)
        #expect(resolved.signer.accountId == expected.accountId)
        #expect(allocator.initiatedTargets == [expected.accountId])
    }

    @Test func signsWithUsernameWhenNoSlotIsFree() async throws {
        allocator.hasFreeSlot = false

        let resolved = try await makeResolver().resolveFirstDelivery(requestId: requestId, session: session)

        #expect(resolved.period == allocator.period)
        #expect(resolved.signer.accountId == fallback.signer.accountId)
        #expect(fallback.contacts == [session.peer.accountId])
    }

    @Test func declinedUsernameKeepsTheErrorForTheCaller() async throws {
        allocator.hasFreeSlot = false
        fallback.decline()

        await #expect(throws: ChatSigningConsentError.declined) {
            try await makeResolver().resolveFirstDelivery(requestId: requestId, session: session)
        }
    }

    @Test func failsWhenClaimDidNotLandInTime() async throws {
        allocator.awaitResult = .failure(NotificationAllocationError.timeout)

        await #expect(throws: NotificationAllocationError.timeout) {
            try await makeResolver().resolveFirstDelivery(requestId: requestId, session: session)
        }

        #expect(fallback.contacts.isEmpty)
    }

    @Test func derivesDistinctAccountsPerRequestAndPeriod() throws {
        let first = try signerManager.makeChatRequestSigner(for: requestId, period: 100).accountId

        #expect(try signerManager.makeChatRequestSigner(for: requestId, period: 101).accountId != first)
        #expect(try signerManager.makeChatRequestSigner(for: "other", period: 100).accountId != first)
        #expect(try signerManager.makeChatAcceptanceSigner(for: requestId, period: 100).accountId != first)
    }

    private func makeResolver() -> ChatRequestDeliveryAccountResolver {
        ChatRequestDeliveryAccountResolver(allocator: allocator, signerManager: signerManager, fallback: fallback)
    }
}
