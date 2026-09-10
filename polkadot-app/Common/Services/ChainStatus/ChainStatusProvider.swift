import Foundation
import AsyncExtensions
import PolkadotUI
import StructuredConcurrency

protocol ChainStatusProviding: Actor {
    nonisolated func statusStream() -> AnyAsyncSequence<[ChainConnectionStatusViewModel]>
    func start()
}

/// Per-chain connection status.
/// One shared instance. The subject always holds a row set, so the first render carries a
/// complete set and a host subscribing later sees live state rather than a re-seed.
actor ChainStatusProvider {
    private static let connectDebounce: Duration = .milliseconds(300)
    private static let deadDwell: TimeInterval = 3

    private let networkStatusService: NetworkStatusProviding
    private let blockProvider: ChainBlockProviding
    private let statementTracker: StatementDeliveryTracking
    private let anchorProvider: ChainLivenessAnchorProviding
    private let logger: LoggerProtocol

    private nonisolated let rowsSubject: AsyncCurrentValueSubject<[ChainConnectionStatusViewModel]>

    private var statuses: [ChainConnectionTarget: NetworkStatus]
    private var blocks: [ChainConnectionTarget: ChainBlockInfo] = [:]
    private var liveness: [ChainConnectionTarget: ChainLiveness] = [:]
    private var statementState: StatementDeliveryState = .noSubscriptions
    private var statusTasks: [Task<Void, Never>] = []
    private var previousIndications: [String: ChainStatusIndication] = [:]
    private var deadSince: [String: Date] = [:]
    private var tickTask: Task<Void, Never>?
    private var isObserving = false
    private var lastEmittedRows: [ChainConnectionStatusViewModel] = []

    init(
        networkStatusService: NetworkStatusProviding,
        blockProvider: ChainBlockProviding,
        statementTracker: StatementDeliveryTracking,
        anchorProvider: ChainLivenessAnchorProviding,
        logger: LoggerProtocol
    ) {
        self.networkStatusService = networkStatusService
        self.blockProvider = blockProvider
        self.statementTracker = statementTracker
        self.anchorProvider = anchorProvider
        self.logger = logger

        let seededStatuses = ChainConnectionTarget.allCases
            .reduce(into: [ChainConnectionTarget: NetworkStatus]()) { $0[$1] = .connecting }

        statuses = seededStatuses
        liveness = ChainConnectionTarget.allCases.reduce(into: [:]) { dict, target in
            dict[target] = ChainLiveness(blockPeriod: target.expectedBlockTime)
        }
        rowsSubject = AsyncCurrentValueSubject(
            Self.makeRows(statuses: seededStatuses, statementState: .noSubscriptions)
        )
    }

    deinit {
        statusTasks.forEach { $0.cancel() }
        tickTask?.cancel()
    }
}

extension ChainStatusProvider: ChainStatusProviding {
    nonisolated func statusStream() -> AnyAsyncSequence<[ChainConnectionStatusViewModel]> {
        rowsSubject.eraseToAnyAsyncSequence()
    }

    func start() {
        guard !isObserving else {
            return
        }

        isObserving = true

        // Sampling runs for the app's lifetime because the top status strip is permanent.
        // A host closing its subscription does not pause sampling.
        Task { [blockProvider] in
            await blockProvider.setActive(true)
        }

        statusTasks = ChainConnectionTarget.allCases.map { target in
            observeStatus(for: target)
        } + [observeBlocks(), observeStatementState()]

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.emitRows()

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

extension ChainStatusProvider {
    func handleStatusUpdate(
        _ status: NetworkStatus,
        for target: ChainConnectionTarget,
        at date: Date = Date()
    ) async {
        let previousStatus = statuses[target]

        guard previousStatus != status else {
            return
        }

        statuses[target] = status

        if status != .connected {
            blocks[target] = nil
            liveness[target]?.clear()
            // Without this a drop-and-reconnect keeps captioning the row with its pre-drop data.
            await blockProvider.clear(for: target)
        } else if previousStatus != .connected, status == .connected {
            let slotCount = liveness[target]?.slotCount ?? 0
            Task {
                do {
                    let anchor = try await anchorProvider.fetchAnchor(for: target, slotCount: slotCount)
                    applyAnchor(anchor, for: target, at: date)
                } catch {
                    logger.error("Failed to fetch anchor for \(target.chainId): \(error)")
                }
            }
        }

        emitRows(at: date)
    }

    func handleBlocksUpdate(
        _ updatedBlocks: [ChainConnectionTarget: ChainBlockInfo],
        at date: Date = Date()
    ) {
        guard updatedBlocks != blocks else {
            return
        }

        blocks = updatedBlocks

        for (target, blockInfo) in updatedBlocks {
            liveness[target]?.record(height: blockInfo.number, at: date)
        }

        emitRows(at: date)
    }

    func handleStatementStateUpdate(_ state: StatementDeliveryState, at date: Date = Date()) {
        guard state != statementState else {
            return
        }

        statementState = state
        emitRows(at: date)
    }

    func emitRows(at date: Date = Date()) {
        let rawRows = Self.makeRows(statuses: statuses, statementState: statementState)
        let indicatedRows = indicateRows(rawRows, at: date)

        guard indicatedRows != lastEmittedRows else { return }

        lastEmittedRows = indicatedRows
        rowsSubject.send(indicatedRows)
    }

    private func indicateRows(
        _ rows: [ChainConnectionStatusViewModel],
        at date: Date
    ) -> [ChainConnectionStatusViewModel] {
        rows.map { row in
            let targetLiveness = ChainConnectionTarget.livenessOwner(forRowId: row.id)
                .flatMap { liveness[$0]?.liveness(at: date) }

            let rawIndication = ChainStatusIndication.resolve(state: row.state, liveness: targetLiveness)
            let indication = applyDwell(to: rawIndication, rowId: row.id, at: date)
            previousIndications[row.id] = indication

            return row.withIndication(indication)
        }
    }

    /// Entering dead is held for `deadDwell` so a flap shorter than that never darkens the strip;
    /// leaving dead is immediate. A row that has never been emitted skips the hold, so a cold
    /// launch with no connectivity reads dead at once instead of normal for three seconds.
    private func applyDwell(
        to indication: ChainStatusIndication,
        rowId: String,
        at date: Date
    ) -> ChainStatusIndication {
        guard let previous = previousIndications[rowId] else {
            return indication
        }

        switch (previous, indication) {
        case (.normal, .normal):
            deadSince[rowId] = nil
            return indication
        case (.normal, .outage):
            deadSince[rowId] = nil
            return indication
        case (.normal, .dead):
            let deadAt = deadSince[rowId] ?? date
            deadSince[rowId] = deadAt
            return date.timeIntervalSince(deadAt) < Self.deadDwell ? previous : indication
        case (.outage, .normal):
            deadSince[rowId] = nil
            return indication
        case (.outage, .outage):
            deadSince[rowId] = nil
            return indication
        case (.outage, .dead):
            let deadAt = deadSince[rowId] ?? date
            deadSince[rowId] = deadAt
            return date.timeIntervalSince(deadAt) < Self.deadDwell ? previous : indication
        case (.dead, .normal):
            deadSince[rowId] = nil
            return indication
        case (.dead, .outage):
            deadSince[rowId] = nil
            return indication
        case (.dead, .dead):
            return indication
        }
    }

    static func makeRows(
        statuses: [ChainConnectionTarget: NetworkStatus],
        statementState: StatementDeliveryState
    ) -> [ChainConnectionStatusViewModel] {
        let targetRows = ChainConnectionTarget.allCases.map { target in
            let state = (statuses[target] ?? .connecting).connectionState

            return ChainConnectionStatusViewModel(
                id: target.chainId,
                title: target.title,
                state: state,
                stateTitle: state.localizedTitle,
                icon: target.statusIcon,
                indication: ChainStatusIndication.resolve(state: state, liveness: nil)
            )
        }

        let statementStoreRow = makeStatementStoreRow(
            chatStatus: statuses[.chat] ?? .connecting,
            statementState: statementState
        )

        return targetRows + [statementStoreRow]
    }

    private static func makeStatementStoreRow(
        chatStatus: NetworkStatus,
        statementState: StatementDeliveryState
    ) -> ChainConnectionStatusViewModel {
        // The Statement Store is reached over Individuality's connection, so its state follows
        // that chain. A delivery failure is the only store-specific signal, forcing it offline.
        let state: ChainConnectionState = statementState == .failed ? .offline : chatStatus.connectionState

        return ChainConnectionStatusViewModel(
            id: ChainConnectionTarget.statementStoreRowId,
            title: "Statement Store",
            state: state,
            stateTitle: state.localizedTitle,
            icon: .statementStore,
            indication: ChainStatusIndication.resolve(state: state, liveness: nil)
        )
    }

    func applyAnchor(_ anchor: ChainLivenessAnchor, for target: ChainConnectionTarget, at date: Date) {
        liveness[target]?.apply(anchor, at: date)
        emitRows(at: date)
    }
}

private extension ChainStatusProvider {
    func observeStatus(for target: ChainConnectionTarget) -> Task<Void, Never> {
        Task { [weak self, networkStatusService, logger] in
            let statusStream = networkStatusService
                .statusStream(for: [target.chainId])
                .withDebounce(for: Self.connectDebounce) { $0 == .connected }

            do {
                for try await status in statusStream {
                    await self?.handleStatusUpdate(status, for: target)
                }
            } catch {
                logger.error("Chain status stream failed for \(target.chainId): \(error)")
            }
        }
    }

    func observeBlocks() -> Task<Void, Never> {
        Task { [weak self, blockProvider, logger] in
            do {
                for try await blocks in blockProvider.blockStream() {
                    await self?.handleBlocksUpdate(blocks)
                }
            } catch {
                logger.error("Chain block stream failed: \(error)")
            }
        }
    }

    func observeStatementState() -> Task<Void, Never> {
        Task { [weak self, statementTracker, logger] in
            do {
                for try await state in statementTracker.stateStream() {
                    await self?.handleStatementStateUpdate(state)
                }
            } catch {
                logger.error("Statement delivery state stream failed: \(error)")
            }
        }
    }
}
