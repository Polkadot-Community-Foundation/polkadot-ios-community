import Clocks
import Foundation
import Testing
@testable import polkadot_app

struct ChatAcceptanceDeliveryServiceTests {
    private let fixture = ChatAcceptanceFixture()
    private let notifier = RecordingAcceptanceNotifier()

    @Test func publishesFromCurrentPeriodAccountAndRecordsPeriod() async throws {
        let store = InMemoryChatAcceptanceStore(candidates: [fixture.makeCandidate(period: nil)])

        await makeService(store: store).deliverUntilDone(messageId: "acceptance")

        let account = try fixture.acceptAccountId(period: fixture.allocator.period)
        #expect(try fixture.senders() == [account])
        #expect(fixture.allocator.initiatedTargets == [account])
        #expect(store.published == [fixture.allocator.period])
        #expect(notifier.notifiedMessageIds == ["acceptance"])
    }

    @Test func doesNothingOnceNoLongerAwaitingPublication() async throws {
        let store = InMemoryChatAcceptanceStore(candidates: [fixture.makeCandidate(period: nil)])
        store.isAwaiting = false

        await makeService(store: store).deliverUntilDone(messageId: "acceptance")

        #expect(try fixture.senders().isEmpty)
    }

    @Test func publishesWithUsernameWhenNoSlotIsFree() async throws {
        fixture.allocator.hasFreeSlot = false
        let store = InMemoryChatAcceptanceStore(candidates: [fixture.makeCandidate(period: nil)])

        await makeService(store: store).deliverUntilDone(messageId: "acceptance")

        #expect(try fixture.senders() == [fixture.fallback.signer.accountId])
        #expect(store.published == [fixture.allocator.period])
        #expect(notifier.notifiedMessageIds == ["acceptance"])
    }

    @Test func marksAcceptanceFailedOnceUsernameIsDeclined() async throws {
        fixture.allocator.hasFreeSlot = false
        fixture.fallback.decline()
        let store = InMemoryChatAcceptanceStore(candidates: [fixture.makeCandidate(period: nil)])

        await makeService(store: store).deliverUntilDone(messageId: "acceptance")

        #expect(try fixture.senders().isEmpty)
        #expect(store.failedCount == 1)
        #expect(notifier.notifiedMessageIds.isEmpty)
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
                signerManager: fixture.signManager,
                statementService: fixture.statementService,
                notifier: notifier,
                fallback: fixture.fallback
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
