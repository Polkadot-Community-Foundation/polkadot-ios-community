import Foundation
import Testing
import ChainRegistry
@testable import polkadot_app

struct TrUAPIV2SpecConnectionPoolTests {
    private let genesis = Data(repeating: 0xAA, count: 32)

    @Test func eachConnectGetsItsOwnSocketAndId() throws {
        let sockets = MockChainSocketResolver([MockChainSocket(), MockChainSocket()])
        let pool = makePool(sockets: sockets)

        let firstId = try #require(pool.connect(genesisHash: genesis))
        let secondId = try #require(pool.connect(genesisHash: genesis))

        #expect(firstId != secondId)
        #expect(sockets.vended.allSatisfy { $0.openCallCount == 1 })
    }

    @Test func sendWritesFrameVerbatimToOwnSocketOnly() throws {
        let sockets = MockChainSocketResolver([MockChainSocket(), MockChainSocket()])
        let pool = makePool(sockets: sockets)
        let firstId = try #require(pool.connect(genesisHash: genesis))
        _ = try #require(pool.connect(genesisHash: genesis))

        let frame = #"{"jsonrpc":"2.0","id":1,"method":"chainHead_v1_follow","params":[true]}"#
        try pool.send(connectionId: firstId, request: frame)

        #expect(sockets.vended[0].sent == [frame])
        #expect(sockets.vended[1].sent.isEmpty)
    }

    @Test func inboundFrameRoutesVerbatimToItsConnection() throws {
        let sockets = MockChainSocketResolver([MockChainSocket(), MockChainSocket()])
        let handler = RecordingChainEventHandler()
        let pool = makePool(sockets: sockets, handler: handler)
        _ = try #require(pool.connect(genesisHash: genesis))
        let secondId = try #require(pool.connect(genesisHash: genesis))

        let frame = #"{"jsonrpc":"2.0","method":"chainHead_v1_followEvent","params":{"subscription":"s1"}}"#
        sockets.vended[1].simulateReceive(frame)

        #expect(handler.responses.count == 1)
        #expect(handler.responses.first?.0 == secondId)
        #expect(handler.responses.first?.1 == frame)
    }

    @Test func socketDeathReportsCloseOnceAndForgetsConnection() throws {
        let sockets = MockChainSocketResolver([MockChainSocket()])
        let handler = RecordingChainEventHandler()
        let pool = makePool(sockets: sockets, handler: handler)
        let connectionId = try #require(pool.connect(genesisHash: genesis))

        sockets.vended[0].simulateClose()
        sockets.vended[0].simulateClose(.resumed)
        sockets.vended[0].simulateReceive("late")

        #expect(handler.closed == [connectionId])
        #expect(handler.responses.isEmpty)
        #expect(throws: TrUAPIChainConnectionError.self) {
            try pool.send(connectionId: connectionId, request: "{}")
        }
    }

    @Test func coreCloseIsSilent() throws {
        let sockets = MockChainSocketResolver([MockChainSocket()])
        let handler = RecordingChainEventHandler()
        let pool = makePool(sockets: sockets, handler: handler)
        let connectionId = try #require(pool.connect(genesisHash: genesis))

        pool.close(connectionId: connectionId)
        sockets.vended[0].simulateClose()

        #expect(sockets.vended[0].closeCallCount == 1)
        #expect(handler.closed.isEmpty)
    }

    @Test func closeDuringOpenStillReportsTheConnection() throws {
        let socket = MockChainSocket()
        socket.onOpen = { $0.simulateClose(.transport(nil)) }
        let handler = RecordingChainEventHandler()
        let pool = makePool(sockets: MockChainSocketResolver([socket]), handler: handler)

        let connectionId = try #require(pool.connect(genesisHash: genesis))

        #expect(handler.closed == [connectionId])
    }

    @Test func unsupportedChainReturnsNil() {
        let pool = makePool(sockets: MockChainSocketResolver([]))

        #expect(pool.connect(genesisHash: genesis) == nil)
    }

    @Test func closeAllClosesEverySocketSilently() throws {
        let sockets = MockChainSocketResolver([MockChainSocket(), MockChainSocket()])
        let handler = RecordingChainEventHandler()
        let pool = makePool(sockets: sockets, handler: handler)
        _ = try #require(pool.connect(genesisHash: genesis))
        _ = try #require(pool.connect(genesisHash: genesis))

        pool.closeAll()

        #expect(sockets.vended.allSatisfy { $0.closeCallCount == 1 })
        #expect(handler.closed.isEmpty)
    }

    @Test func registryResolverMapsGenesisToChainSocket() throws {
        let chainRegistry = MockChainRegistry()
        let chain = ChainMock.makeChainModel(from: ChainMock.makeRemoteChain(name: "TestChain"), order: 0)
        chainRegistry.chainsByGenesis[genesis.toHex()] = chain
        let pool = TrUAPIV2SpecConnectionPool.makeChainConnections(chainRegistry: chainRegistry, logger: StubLogger())

        #expect(pool.connect(genesisHash: genesis) == nil)

        let socket = MockChainSocket()
        chainRegistry.chainSocketsById[chain.chainId] = socket

        #expect(pool.connect(genesisHash: genesis) != nil)
        #expect(socket.openCallCount == 1)
        #expect(chainRegistry.chainSocketAttempts == [0, 1])
    }

    @Test func nodeAttemptGrowsPerChain() throws {
        let otherGenesis = Data(repeating: 0xBB, count: 32)
        let sockets = MockChainSocketResolver([MockChainSocket(), MockChainSocket(), MockChainSocket()])
        let pool = makePool(sockets: sockets)

        _ = try #require(pool.connect(genesisHash: genesis))
        _ = try #require(pool.connect(genesisHash: genesis))
        _ = try #require(pool.connect(genesisHash: otherGenesis))

        #expect(sockets.requests.map(\.attempt) == [0, 1, 0])
        #expect(sockets.requests.map(\.genesisHash) == [genesis, genesis, otherGenesis])
    }

    // MARK: - Foreground revalidation

    @Test func shortBackgroundProbesEverySocket() throws {
        let sockets = MockChainSocketResolver([MockChainSocket(), MockChainSocket()])
        let applicationHandler = MockApplicationHandler()
        let clock = ManualDateSource()
        let pool = makePool(sockets: sockets, applicationHandler: applicationHandler, clock: clock)
        _ = try #require(pool.connect(genesisHash: genesis))
        _ = try #require(pool.connect(genesisHash: genesis))

        applicationHandler.simulateDidEnterBackground()
        clock.advance(by: 29)
        applicationHandler.simulateWillEnterForeground()

        #expect(sockets.vended.allSatisfy { $0.probeTimeouts == [5] && $0.expireCallCount == 0 })
    }

    @Test func longBackgroundExpiresEverySocket() throws {
        let sockets = MockChainSocketResolver([MockChainSocket(), MockChainSocket()])
        let applicationHandler = MockApplicationHandler()
        let clock = ManualDateSource()
        let pool = makePool(sockets: sockets, applicationHandler: applicationHandler, clock: clock)
        _ = try #require(pool.connect(genesisHash: genesis))
        _ = try #require(pool.connect(genesisHash: genesis))

        applicationHandler.simulateDidEnterBackground()
        clock.advance(by: 30)
        applicationHandler.simulateWillEnterForeground()

        #expect(sockets.vended.allSatisfy { $0.expireCallCount == 1 && $0.probeTimeouts.isEmpty })
    }

    @Test func expiredSocketIsReportedClosed() throws {
        let sockets = MockChainSocketResolver([MockChainSocket()])
        let handler = RecordingChainEventHandler()
        let applicationHandler = MockApplicationHandler()
        let clock = ManualDateSource()
        let pool = makePool(sockets: sockets, handler: handler, applicationHandler: applicationHandler, clock: clock)
        let connectionId = try #require(pool.connect(genesisHash: genesis))

        applicationHandler.simulateDidEnterBackground()
        clock.advance(by: 60)
        applicationHandler.simulateWillEnterForeground()
        sockets.vended[0].simulateClose(.resumed)

        #expect(handler.closed == [connectionId])
    }

    @Test func backgroundDoesNotRevalidate() throws {
        let sockets = MockChainSocketResolver([MockChainSocket()])
        let handler = RecordingChainEventHandler()
        let applicationHandler = MockApplicationHandler()
        let clock = ManualDateSource()
        let pool = makePool(sockets: sockets, handler: handler, applicationHandler: applicationHandler, clock: clock)
        _ = try #require(pool.connect(genesisHash: genesis))

        applicationHandler.simulateDidEnterBackground()
        clock.advance(by: 600)

        #expect(sockets.vended[0].expireCallCount == 0)
        #expect(sockets.vended[0].probeTimeouts.isEmpty)
        #expect(sockets.vended[0].closeCallCount == 0)
        #expect(handler.closed.isEmpty)
    }

    @Test func transportDeathWhileBackgroundedIsReported() throws {
        let sockets = MockChainSocketResolver([MockChainSocket()])
        let handler = RecordingChainEventHandler()
        let applicationHandler = MockApplicationHandler()
        let pool = makePool(sockets: sockets, handler: handler, applicationHandler: applicationHandler)
        let connectionId = try #require(pool.connect(genesisHash: genesis))

        applicationHandler.simulateDidEnterBackground()
        sockets.vended[0].simulateClose(.peerClosed)

        #expect(handler.closed == [connectionId])
    }

    @Test func becomingActiveWithoutBackgroundRevalidatesNothing() throws {
        let sockets = MockChainSocketResolver([MockChainSocket()])
        let applicationHandler = MockApplicationHandler()
        let clock = ManualDateSource()
        let pool = makePool(sockets: sockets, applicationHandler: applicationHandler, clock: clock)
        _ = try #require(pool.connect(genesisHash: genesis))

        applicationHandler.simulateDidBecomeActive()
        applicationHandler.simulateWillEnterForeground()

        #expect(sockets.vended[0].expireCallCount == 0)
        #expect(sockets.vended[0].probeTimeouts.isEmpty)
    }

    @Test func socketReleasedByCoreIsNotRevalidated() throws {
        let sockets = MockChainSocketResolver([MockChainSocket()])
        let applicationHandler = MockApplicationHandler()
        let clock = ManualDateSource()
        let pool = makePool(sockets: sockets, applicationHandler: applicationHandler, clock: clock)
        let connectionId = try #require(pool.connect(genesisHash: genesis))

        applicationHandler.simulateDidEnterBackground()
        pool.close(connectionId: connectionId)
        clock.advance(by: 60)
        applicationHandler.simulateWillEnterForeground()

        #expect(sockets.vended[0].expireCallCount == 0)
    }

    @Test func socketOpenedWhileBackgroundedIsRevalidated() throws {
        let sockets = MockChainSocketResolver([MockChainSocket()])
        let applicationHandler = MockApplicationHandler()
        let clock = ManualDateSource()
        let pool = makePool(sockets: sockets, applicationHandler: applicationHandler, clock: clock)

        applicationHandler.simulateDidEnterBackground()
        _ = try #require(pool.connect(genesisHash: genesis))
        clock.advance(by: 1)
        applicationHandler.simulateWillEnterForeground()

        #expect(sockets.vended[0].probeTimeouts == [5])
    }
}

private extension TrUAPIV2SpecConnectionPoolTests {
    func makePool(
        sockets: MockChainSocketResolver,
        handler: RecordingChainEventHandler? = nil,
        applicationHandler: MockApplicationHandler = MockApplicationHandler(),
        clock: ManualDateSource = ManualDateSource()
    ) -> TrUAPIV2SpecConnectionPool {
        let pool = TrUAPIV2SpecConnectionPool(
            socketResolver: { genesisHash, attempt in sockets.next(genesisHash: genesisHash, attempt: attempt) },
            applicationHandler: applicationHandler,
            resumePolicy: .init(expiryThreshold: 30, probeTimeout: 5),
            logger: StubLogger(),
            now: { clock.now }
        )
        pool.eventHandler = handler
        return pool
    }
}
