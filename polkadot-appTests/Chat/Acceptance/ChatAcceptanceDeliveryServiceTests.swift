import Clocks
import Foundation
import Testing
@testable import polkadot_app

struct ChatAcceptanceDeliveryServiceTests {
    private let fixture = ChatAcceptanceFixture()
    private let activator = RecordingSenderDeviceActivator()

    @Test func publishesFromCurrentPeriodAccountThenActivatesRequesterDevice() async throws {
        let store = InMemoryChatAcceptanceStore(candidates: [fixture.makeCandidate(period: nil)])

        await makeService(store: store).deliverUntilDone(messageId: "acceptance")

        let account = try fixture.acceptAccountId(period: fixture.allocator.period)
        #expect(try fixture.senders() == [account])
        #expect(fixture.allocator.initiatedTargets == [account])
        #expect(activator.activations == [fixture.requestId])
        #expect(store.published == [fixture.allocator.period])
    }

    @Test func doesNothingOnceNoLongerAwaitingPublication() async throws {
        let store = InMemoryChatAcceptanceStore(candidates: [fixture.makeCandidate(period: nil)])
        store.isAwaiting = false

        await makeService(store: store).deliverUntilDone(messageId: "acceptance")

        #expect(try fixture.senders().isEmpty)
        #expect(activator.activations.isEmpty)
    }

    @Test func keepsRetryingWithoutSlotAndPublishesNothing() async throws {
        fixture.allocator.hasFreeSlot = false
        let store = InMemoryChatAcceptanceStore(candidates: [fixture.makeCandidate(period: nil)])
        store.awaitingReadsLeft = 3

        await makeService(store: store).deliverUntilDone(messageId: "acceptance")

        #expect(store.awaitingReadsLeft == -1)
        #expect(try fixture.senders().isEmpty)
        #expect(activator.activations.isEmpty)
        #expect(store.published.isEmpty)
    }

    @Test func identityAccountNeverSignsAcceptance() async throws {
        let store = InMemoryChatAcceptanceStore(candidates: [fixture.makeCandidate(period: nil)])

        await makeService(store: store).deliverUntilDone(messageId: "acceptance")

        #expect(try !fixture.senders().contains(fixture.identityAccountId()))
    }
}

private extension ChatAcceptanceDeliveryServiceTests {
    func makeService(store: ChatAcceptanceStoring) -> ChatAcceptanceDeliveryService {
        ChatAcceptanceDeliveryService(
            dependencies: ChatAcceptanceDeliveryDependencies(
                store: store,
                allocator: fixture.allocator,
                signers: fixture.signers,
                statementService: fixture.statementService,
                deviceActivator: activator
            ),
            execution: ChatRequestDeliveryExecution(
                backgroundExecutor: InlineBackgroundExecutor(),
                clock: ImmediateClock()
            ),
            issueDiagnostics: .recording(),
            logger: MockLogger()
        )
    }
}
