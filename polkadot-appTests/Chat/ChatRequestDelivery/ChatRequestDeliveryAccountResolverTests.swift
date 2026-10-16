import Foundation
import Individuality
import MessageExchangeKit
import Testing
@testable import polkadot_app

struct ChatRequestDeliveryAccountResolverTests {
    private let requestId = "request"
    private let allocator = StubNotificationAllocator()
    private let signers =
        ChatRequestDeliverySigners(signManager: ChatSignerManager(entropyManager: FixedRootEntropyManager()))
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
        let expected = try signers.anonymous(requestId: requestId, period: allocator.period)

        let resolved = try await makeResolver().resolveFirstDelivery(requestId: requestId, session: session)

        #expect(resolved.period == allocator.period)
        #expect(resolved.signer.accountId == expected.signer.accountId)
        #expect(allocator.initiatedTargets == [expected.signer.accountId])
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
        let first = try signers.anonymous(requestId: requestId, period: 100).signer.accountId

        #expect(try signers.anonymous(requestId: requestId, period: 101).signer.accountId != first)
        #expect(try signers.anonymous(requestId: "other", period: 100).signer.accountId != first)
    }

    private func makeResolver() -> ChatRequestDeliveryAccountResolver {
        ChatRequestDeliveryAccountResolver(allocator: allocator, signers: signers, fallback: fallback)
    }
}
