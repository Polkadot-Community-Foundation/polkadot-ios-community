import Foundation
import Testing
@testable import polkadot_app

struct ChatAcceptanceRenewerTests {
    private let fixture = ChatAcceptanceFixture()
    private let unacknowledged = RecordingIssueDiagnostic()

    @Test func acknowledgedAcceptanceIsMarkedDeliveredWithoutPublishing() async throws {
        let store =
            InMemoryChatAcceptanceStore(candidates: [fixture.makeCandidate(period: fixture.allocator.period - 1)])
        store.isAcknowledged = true

        await makeRenewer(store: store).renew()

        #expect(store.acknowledgedCount == 1)
        #expect(try fixture.senders().isEmpty)
    }

    @Test func stopsRenewingAfterSevenDaysAndReportsIt() async throws {
        let sentAt = fixture.now.addingTimeInterval(-7 * 86_400 - 1)
        let store = InMemoryChatAcceptanceStore(candidates: [fixture.makeCandidate(period: 1, sentAt: sentAt)])

        await makeRenewer(store: store).renew()

        #expect(try fixture.senders().isEmpty)
        #expect(unacknowledged.failureCount == 1)
    }

    @Test func stalePeriodRepublishesFromFreshAccount() async throws {
        let store =
            InMemoryChatAcceptanceStore(candidates: [fixture.makeCandidate(period: fixture.allocator.period - 1)])

        await makeRenewer(store: store).renew()

        #expect(try fixture.senders() == [fixture.acceptAccountId(period: fixture.allocator.period)])
        #expect(store.published == [fixture.allocator.period])
    }

    @Test func staleAcceptanceWithoutSlotIsNotPublished() async throws {
        fixture.allocator.hasFreeSlot = false
        let store =
            InMemoryChatAcceptanceStore(candidates: [fixture.makeCandidate(period: fixture.allocator.period - 1)])

        await makeRenewer(store: store).renew()

        #expect(try fixture.senders().isEmpty)
        #expect(store.published.isEmpty)
    }

    @Test func currentPeriodCopyInStoreIsLeftAlone() async throws {
        let candidate = fixture.makeCandidate(period: fixture.allocator.period)
        let signer = try fixture.signers.signer(requestId: fixture.requestId, period: fixture.allocator.period)
        try await fixture.statementService.send(candidate, signer: signer.signer)
        let store = InMemoryChatAcceptanceStore(candidates: [candidate])

        await makeRenewer(store: store).renew()

        #expect(try fixture.senders() == [signer.signer.accountId])
        #expect(store.published.isEmpty)
    }

    @Test func missingCurrentPeriodCopyIsResentFromSameAccount() async throws {
        let store = InMemoryChatAcceptanceStore(candidates: [fixture.makeCandidate(period: fixture.allocator.period)])

        await makeRenewer(store: store).renew()

        #expect(try fixture.senders() == [fixture.acceptAccountId(period: fixture.allocator.period)])
        #expect(fixture.allocator.initiatedTargets.isEmpty)
        #expect(store.published.isEmpty)
    }
}

private extension ChatAcceptanceRenewerTests {
    func makeRenewer(store: ChatAcceptanceStoring) -> ChatAcceptanceRenewer {
        ChatAcceptanceRenewer(
            dependencies: ChatAcceptanceRenewalDependencies(
                store: store,
                allocator: fixture.allocator,
                signers: fixture.signers,
                statementService: fixture.statementService
            ),
            dateProvider: MockDateProvider(now: fixture.now),
            issueDiagnostics: .recording(unacknowledged: unacknowledged),
            logger: MockLogger()
        )
    }
}
