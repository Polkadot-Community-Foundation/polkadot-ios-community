import Foundation
import Testing
import AsyncExtensions
import SubstrateSdk
import PolkadotUI
@testable import polkadot_app

struct ChainStatusProviderTests {
    @Test("A row with no prior emission emits its raw indication")
    func firstEmissionRaw() async {
        let provider = makeProvider()
        let t0 = Date()

        await provider.handleStatusUpdate(.waitingForNetwork, for: .chat)
        await provider.emitRows(at: t0)

        let chatRow = await currentChatRow(from: provider)

        #expect(chatRow?.indication == .dead, "first emission with offline state is raw dead")
    }

    @Test("A stalling chain produces outage")
    func stallingChainOutage() async {
        // Chat is a 2s chain: 30s window, 15 slots. Blocks arrive on time up to t0+30, then stop.
        let provider = makeProvider()
        let t0 = Date()

        await provider.handleStatusUpdate(.connected, for: .chat, at: t0)

        for index in 0 ... 15 {
            let date = t0.addingTimeInterval(Double(index) * 2)
            let blockInfo = ChainBlockInfo(
                number: BlockNumber(index),
                receivedAt: date,
                finalizedNumber: nil
            )
            await provider.handleBlocksUpdate([.chat: blockInfo], at: date)
        }

        var chatRow = await currentChatRow(from: provider)
        #expect(chatRow?.indication == .normal, "15 blocks over the 15-slot window is liveness 1")

        // 10s into the stall the window start is t0+10, so the anchor is height 5 and 10 of the
        // 15 slots carry a block. The exact value pins the sample timestamps: if they collapsed
        // onto one instant, the anchor would be the head and this would read 0.
        await provider.emitRows(at: t0.addingTimeInterval(40))

        chatRow = await currentChatRow(from: provider)
        #expect(chatRow?.indication == .outage(liveness: 10.0 / 15.0))

        // Window start is t0+31, past every sample: the anchor collapses onto the head and
        // liveness reads 0.
        await provider.emitRows(at: t0.addingTimeInterval(61))

        chatRow = await currentChatRow(from: provider)
        #expect(chatRow?.indication == .outage(liveness: 0))
    }

    @Test("Disconnect clears liveness so reconnect does not inherit pre-drop history")
    func disconnectClearsLiveness() async {
        let provider = makeProvider()
        let t0 = Date()

        await provider.handleStatusUpdate(.connected, for: .chat)

        for index in 0 ... 10 {
            let blockInfo = ChainBlockInfo(
                number: BlockNumber(index),
                receivedAt: t0.addingTimeInterval(Double(index) * 2),
                finalizedNumber: nil
            )
            await provider.handleBlocksUpdate([.chat: blockInfo])
        }

        await provider.emitRows(at: t0.addingTimeInterval(20))

        await provider.handleStatusUpdate(.waitingForNetwork, for: .chat)
        await provider.emitRows(at: t0.addingTimeInterval(30))

        var chatRow = await currentChatRow(from: provider)
        #expect(chatRow?.indication == .dead)

        await provider.handleStatusUpdate(.connected, for: .chat)
        await provider.emitRows(at: t0.addingTimeInterval(31))

        chatRow = await currentChatRow(from: provider) ?? chatRow

        #expect(
            chatRow?.indication == .normal,
            "after reconnect, liveness was cleared so history does not persist"
        )
    }

    @Test("Recovery within dwell window clears deadSince so fresh dwell can start")
    func recoveryWithinDwellClearsDeadSince() async {
        // Fails if deadSince[rowId] = nil is removed from the (.normal, .normal) arm of applyDwell.
        // A fresh dwell must start when entering dead again, not reuse an old deadSince timestamp.
        let provider = makeProvider()
        let t0 = Date()

        // Step 1: Connect at t0, row is normal
        await provider.handleStatusUpdate(.connected, for: .chat, at: t0)
        await provider.emitRows(at: t0)

        var chatRow = await currentChatRow(from: provider)
        #expect(chatRow?.indication == .normal)

        // Step 2: Go offline at t0+1, dwell holds so row stays normal
        await provider.handleStatusUpdate(.waitingForNetwork, for: .chat, at: t0 + 1)
        await provider.emitRows(at: t0 + 1)

        chatRow = await currentChatRow(from: provider)
        #expect(chatRow?.indication == .normal, "dwell holds dead within 3s window")

        // Step 3: Reconnect at t0+2 (within dwell), recovery clears deadSince
        await provider.handleStatusUpdate(.connected, for: .chat, at: t0 + 2)
        await provider.emitRows(at: t0 + 2)

        chatRow = await currentChatRow(from: provider)
        #expect(chatRow?.indication == .normal)

        // Step 4: Go offline again at t0+10, a fresh dwell begins (not reusing old t0+1)
        await provider.handleStatusUpdate(.waitingForNetwork, for: .chat, at: t0 + 10)
        await provider.emitRows(at: t0 + 10)

        chatRow = await currentChatRow(from: provider)
        #expect(
            chatRow?.indication == .normal,
            "fresh dwell starts at t0+10, so nothing has elapsed yet and the dwell still holds"
        )

        // Step 5: At t0+13.1, the fresh dwell (3s from t0+10) expires and row goes dead
        await provider.emitRows(at: t0.addingTimeInterval(13.1))

        chatRow = await currentChatRow(from: provider)
        #expect(
            chatRow?.indication == .dead,
            "fresh dwell expired at t0+13: (t0+13.1 - t0+10 = 3.1s > 3s dwell)"
        )
    }

    @Test("Statement store row state follows chat chain and delivery failure forces it offline")
    func statementStoreRowStateTracking() async {
        let testCases: [(
            status: NetworkStatus,
            trackerState: StatementDeliveryState,
            expectedState: ChainConnectionState,
            expectedIndication: ChainStatusIndication
        )] = [
            (.connected, .active, .connected, .normal),
            (.connected, .failed, .offline, .dead),
            (.connected, .noSubscriptions, .connected, .normal),
            (.waitingForNetwork, .active, .offline, .dead),
            (.connecting, .active, .connecting, .dead)
        ]

        // The tracker state is set before the chain status so that the row's first emission
        // already carries it. Driving it the other way round emits a normal row first, and the
        // dead dwell then holds that normal for 3s — which is the dwell's job, covered below.
        for testCase in testCases {
            let provider = makeProvider()
            let t0 = Date()

            await provider.handleStatementStateUpdate(testCase.trackerState, at: t0)
            await provider.handleStatusUpdate(testCase.status, for: .chat, at: t0)
            await provider.emitRows(at: t0)

            let storeRow = await currentStoreRow(from: provider)
            let inputs = "chat \(testCase.status), tracker \(testCase.trackerState)"

            #expect(storeRow?.state == testCase.expectedState, "\(inputs): state")
            #expect(storeRow?.indication == testCase.expectedIndication, "\(inputs): indication")
        }
    }

    @Test("Delivery failure on an already-normal store row goes dead after the dwell")
    func statementStoreRowFailureDarkensAfterDwell() async {
        // The realistic path: the store row is live, then delivery fails while Individuality
        // stays connected. The row's state turns offline at once; the ring darkens after the 3s
        // dwell, like every other row entering dead.
        let provider = makeProvider()
        let t0 = Date()

        await provider.handleStatusUpdate(.connected, for: .chat, at: t0)
        await provider.handleStatementStateUpdate(.active, at: t0)
        await provider.emitRows(at: t0)

        var storeRow = await currentStoreRow(from: provider)
        #expect(storeRow?.state == .connected)
        #expect(storeRow?.indication == .normal)

        await provider.handleStatementStateUpdate(.failed, at: t0 + 1)

        storeRow = await currentStoreRow(from: provider)
        #expect(storeRow?.state == .offline, "state turns offline immediately")
        #expect(storeRow?.indication == .normal, "dwell holds the ring for 3s")

        await provider.emitRows(at: t0.addingTimeInterval(4.1))

        storeRow = await currentStoreRow(from: provider)
        let chatRow = await currentChatRow(from: provider)
        #expect(storeRow?.indication == .dead, "dwell expired, ring goes dead")
        #expect(chatRow?.indication == .normal, "Individuality is unaffected by a store failure")
    }

    @Test("Store row state matches chat row state for all non-failed tracker states")
    func statementStoreRowMatchesChatRowState() async {
        let statuses: [NetworkStatus] = [.connected, .connecting, .waitingForNetwork]
        let trackerStates: [StatementDeliveryState] = [.active, .noSubscriptions]

        for status in statuses {
            for trackerState in trackerStates {
                let provider = makeProvider()
                let t0 = Date()

                await provider.handleStatusUpdate(status, for: .chat, at: t0)
                await provider.handleStatementStateUpdate(trackerState, at: t0)
                await provider.emitRows(at: t0)

                let chatRow = await currentChatRow(from: provider)
                let storeRow = await currentStoreRow(from: provider)

                #expect(
                    storeRow?.state == chatRow?.state,
                    "chat \(status), tracker \(trackerState)"
                )
            }
        }
    }

    @Test("Store row arc equals chat row arc with full liveness window")
    func statementStoreRowArcEqualsChatRowArc() async {
        // Chat is a 2s chain: 30s window, 15 slots. The blocks have to span a full window:
        // liveness reads nil until one has elapsed, and both rows would then compare equal at
        // .normal while asserting nothing.
        let provider = makeProvider()
        let t0 = Date()

        await provider.handleStatusUpdate(.connected, for: .chat, at: t0)
        await provider.handleStatementStateUpdate(.active, at: t0)

        for index in 0 ... 15 {
            let date = t0.addingTimeInterval(Double(index) * 2)
            let blockInfo = ChainBlockInfo(
                number: BlockNumber(index),
                receivedAt: date,
                finalizedNumber: nil
            )
            await provider.handleBlocksUpdate([.chat: blockInfo], at: date)
        }

        // Window start is t0+10, so anchor is height 5, and 10 of 15 slots carry a block.
        await provider.emitRows(at: t0.addingTimeInterval(40))

        let chatRow = await currentChatRow(from: provider)
        let storeRow = await currentStoreRow(from: provider)

        #expect(
            chatRow?.indication == .outage(liveness: 10.0 / 15.0),
            "Chat row should show outage with liveness 10/15"
        )

        #expect(
            storeRow?.indication == .outage(liveness: 10.0 / 15.0),
            "Store row should show same outage as chat row"
        )

        #expect(
            storeRow?.indication == chatRow?.indication,
            "Store row indication must equal chat row indication exactly"
        )
    }

    @Test("Cold connect fetches exactly one anchor")
    func coldConnectFetchesOneAnchor() async {
        // A stalled anchor, not a healthy one: span 90 over a 30s window is 5 of 15 slots, so
        // the row can only read outage if the anchor was actually applied. A healthy anchor
        // would read normal, which is also what an un-applied anchor reads.
        let mockAnchor = MockChainLivenessAnchorProvider()
        await mockAnchor.setAnchor(ChainLivenessAnchor(headHeight: 100, chainTimeSpanSeconds: 90))
        let provider = makeProvider(anchorProvider: mockAnchor)
        let t0 = Date()

        await provider.handleStatusUpdate(.connected, for: .chat, at: t0)

        // Give the async fetch task a moment to complete
        try? await Task.sleep(for: .milliseconds(100))

        #expect(await mockAnchor.fetchAnchorCalls.count == 1)
        #expect(await mockAnchor.fetchAnchorCalls[0].target == .chat)
        #expect(await mockAnchor.fetchAnchorCalls[0].slotCount == 15)

        let chatRow = await currentChatRow(from: provider)
        #expect(chatRow?.indication == .outage(liveness: 5.0 / 15.0), "anchor was applied")
    }

    @Test("Status change not into connected does not fetch anchor")
    func notConnectedDoesNotFetchAnchor() async {
        let mockAnchor = MockChainLivenessAnchorProvider()
        let provider = makeProvider(anchorProvider: mockAnchor)
        let t0 = Date()

        await provider.handleStatusUpdate(.connecting, for: .chat, at: t0)
        await provider.handleStatusUpdate(.waitingForNetwork, for: .chat, at: t0)

        try? await Task.sleep(for: .milliseconds(100))

        #expect(await mockAnchor.fetchAnchorCalls.isEmpty)
    }

    @Test("fetchAnchor error leaves row un-anchored")
    func fetchAnchorErrorLeavesRowUnanchored() async {
        let mockAnchor = MockChainLivenessAnchorProvider()
        await mockAnchor.setError(NSError(domain: "test", code: -1))
        let provider = makeProvider(anchorProvider: mockAnchor)
        let t0 = Date()

        await provider.handleStatusUpdate(.connected, for: .chat, at: t0)

        try? await Task.sleep(for: .milliseconds(100))

        let chatRow = await currentChatRow(from: provider)
        #expect(chatRow?.indication == .normal, "error does not crash; row stays on default indication")
    }
}

private extension ChainStatusProviderTests {
    func makeProvider(anchorProvider: ChainLivenessAnchorProviding? = nil) -> ChainStatusProvider {
        ChainStatusProvider(
            networkStatusService: MockNetworkStatusService(),
            blockProvider: MockChainBlockProvider(),
            statementTracker: MockStatementDeliveryTracker(),
            anchorProvider: anchorProvider ?? MockChainLivenessAnchorProvider(),
            logger: StubLogger()
        )
    }

    func currentChatRow(from provider: ChainStatusProvider) async -> ChainConnectionStatusViewModel? {
        let rows = try? await provider.statusStream().first { _ in true }
        return rows?.first { $0.id == ChainConnectionTarget.chat.chainId }
    }

    func currentStoreRow(from provider: ChainStatusProvider) async -> ChainConnectionStatusViewModel? {
        let rows = try? await provider.statusStream().first { _ in true }
        return rows?.first { $0.id == ChainConnectionTarget.statementStoreRowId }
    }
}
