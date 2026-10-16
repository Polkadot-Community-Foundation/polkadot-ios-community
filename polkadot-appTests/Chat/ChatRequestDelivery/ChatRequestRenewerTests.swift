import Foundation
import MessageExchangeKit
import SubstrateSdk
import Testing
@testable import polkadot_app

struct ChatRequestRenewerTests {
    private let allocator = StubNotificationAllocator()
    private let store = InMemoryChatRequestRenewalStore()
    private let outgoingService = RecordingOutgoingChatRequestService()
    private let signers =
        ChatRequestDeliverySigners(signManager: ChatSignerManager(entropyManager: FixedRootEntropyManager()))
    private let fallback = FakeIdentitySigningFallback(signer: StubStatementSigner(accountId: Data(
        repeating: 0x0C,
        count: 32
    )))

    @Test func renewsRequestOfEarlierPeriodFromFreshAccount() async throws {
        store.candidates = [candidate("request", period: 99)]
        let fresh = try account("request", period: 100)

        await makeRenewer().renew()

        #expect(allocator.initiatedTargets == [fresh])
        #expect(outgoingService.sentSigners == [fresh])
        #expect(store.periodUpdates.map(\.period) == [100])
    }

    @Test func renewsStaleRequestWithUsernameWhenNoSlotIsClaimed() async {
        allocator.hasFreeSlot = false
        store.candidates = [candidate("request", period: 99)]

        await makeRenewer().renew()

        #expect(outgoingService.sentSigners == [fallback.signer.accountId])
        #expect(store.periodUpdates.map(\.period) == [100])
    }

    @Test func failsStaleRequestWhenUsernameIsDeclined() async {
        allocator.hasFreeSlot = false
        fallback.decline()
        store.candidates = [candidate("request", period: 99)]

        await makeRenewer().renew()

        #expect(outgoingService.sentSigners.isEmpty)
        #expect(store.periodUpdates.isEmpty)
        #expect(store.failed == ["request"])
    }

    @Test func keepsUsernameCopyOfCurrentPeriodWhileStored() async {
        fallback.grantConsent()
        store.candidates = [candidate("request", period: 100)]
        outgoingService.storedSigners = [fallback.signer.accountId]

        await makeRenewer().renew()

        #expect(outgoingService.sentSigners.isEmpty)
    }

    @Test func resendsMissingCopyWithUsernameWhenConsented() async {
        fallback.grantConsent()
        store.candidates = [candidate("request", period: 100)]

        await makeRenewer().renew()

        #expect(outgoingService.sentSigners == [fallback.signer.accountId])
    }

    @Test func givesNewestRequestTheSlotWhenSlotsRunShort() async throws {
        allocator.freeSlotCount = 1
        store.candidates = [candidate("newer", period: 99), candidate("older", period: 99)]

        await makeRenewer().renew()

        #expect(try Set(outgoingService.sentSigners) == [account("newer", period: 100), fallback.signer.accountId])
        #expect(fallback.contacts.count == 1)
    }

    @Test func resendsRequestOfCurrentPeriodMissingFromStore() async throws {
        store.candidates = [candidate("request", period: 100)]

        await makeRenewer().renew()

        #expect(try outgoingService.sentSigners == [account("request", period: 100)])
        #expect(allocator.initiatedTargets.isEmpty)
        #expect(store.periodUpdates.isEmpty)
    }

    @Test func leavesRequestOfCurrentPeriodAloneWhileStored() async throws {
        store.candidates = [candidate("request", period: 100)]
        outgoingService.storedSigners = try [account("request", period: 100)]

        await makeRenewer().renew()

        #expect(outgoingService.sentSigners.isEmpty)
    }

    @Test func keepsOldPeriodWhenRenewedRequestFailsToPublish() async {
        store.candidates = [candidate("request", period: 99)]
        outgoingService.failures = [TestRenewalError()]

        await makeRenewer().renew()

        #expect(store.periodUpdates.isEmpty)
    }

    private func makeRenewer() -> ChatRequestRenewer {
        ChatRequestRenewer(
            store: store,
            signing: ChatRequestRenewalSigning(allocator: allocator, signers: signers, fallback: fallback),
            outgoingService: outgoingService,
            diagnostics: .noop
        )
    }

    private func account(_ requestId: String, period: UInt32) throws -> AccountId {
        try signers.anonymous(requestId: requestId, period: period).signer.accountId
    }

    private func candidate(_ requestId: String, period: UInt32) -> ChatRequestRenewalCandidate {
        ChatRequestRenewalCandidate(
            message: Chat.RequestMessage(
                messageId: requestId,
                timestamp: 1,
                content: .v1(Chat.RequestContentV1(pushToken: nil, welcomeMessage: nil))
            ),
            session: MessageExchange.SessionRequest(
                own: MessageExchange.Own(signKeyId: "//wallet//main", encryptionKeyId: "main", pin: nil),
                peer: MessageExchange.Peer(
                    accountId: Data(repeating: 9, count: 32),
                    publicKey: Data(repeating: 8, count: 32),
                    pin: nil,
                    devices: []
                )
            ),
            period: period
        )
    }
}

private struct TestRenewalError: Error {}
