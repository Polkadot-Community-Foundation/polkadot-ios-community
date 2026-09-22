import BigInt
import Coinage
import CommonService
import Foundation
import Operation_iOS
import SubstrateSdk

/// Monitors coinage transfer lifecycle for both directions, driven entirely off the durability layer
/// keyed by `groupId = messageId` — no bespoke claim-status persistence:
/// - Incoming: claims transferred coins (with retry) via ``ClaimCoinsServicing``.
/// - Outgoing: derives Appendix-A payment status via ``CoinageTransferStatusServicing``.
protocol CoinageTransferMonitoring: AsyncApplicationServicing {}

final class CoinageTransferMonitor {
    private let coinageService: any CoinageServicing
    private let messageProviderFactory: ChatMessageDataProviderMaking
    private let claimStatusStore: ClaimStatusStore
    private let claimTransferStore: any ClaimTransferStoring
    private let logger: LoggerProtocol

    /// Top-level tasks that listen to the CoreData message streams.
    private var incomingTransfersSubscription: Task<Void, Never>?
    private var outgoingTransfersSubscription: Task<Void, Never>?

    /// Per-message tasks keyed by messageId. Each resolves independently, avoiding head-of-line
    /// blocking across messages.
    private let taskRegistry = ActiveTaskRegistry()

    init(
        coinageService: any CoinageServicing,
        storageFacade: StorageFacadeProtocol,
        claimStatusStore: ClaimStatusStore,
        claimTransferStore: (any ClaimTransferStoring)? = nil,
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.coinageService = coinageService
        self.claimStatusStore = claimStatusStore
        self.claimTransferStore = claimTransferStore
            ?? ClaimTransferCoreDataStore(storageFacade: storageFacade)
        self.logger = logger

        let repositoryFactory = ChatMessageRepositoryFactory(storageFacade: storageFacade)
        messageProviderFactory = ChatMessageDataProviderFactory(
            repositoryFactory: repositoryFactory,
            operationQueue: operationQueue,
            logger: logger
        )
    }
}

extension CoinageTransferMonitor: CoinageTransferMonitoring {
    func setup() async {
        subscribeIncomingMessages()
        subscribeOutgoingMessages()
    }

    func throttle() async {
        incomingTransfersSubscription?.cancel()
        outgoingTransfersSubscription?.cancel()
        await taskRegistry.cancelAll()
    }
}

// MARK: - Incoming (claim)

private extension CoinageTransferMonitor {
    func subscribeIncomingMessages() {
        logger.debug("Going to subscribe to incoming messages")

        incomingTransfersSubscription = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = messageProviderFactory.subscribeMessages(with: .incomingCoinageSendMessages())
                for try await messages in stream {
                    try Task.checkCancellation()

                    logger.debug("Found \(messages.count) incoming coinage messages")

                    for message in messages {
                        await startIncoming(for: message)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Coinage claim subscription failed: \(error)")
            }
        }
    }

    func startIncoming(for message: Chat.LocalMessage) async {
        guard case let .coinageSend(content) = message.content else { return }
        let messageId = message.messageId
        guard await taskRegistry.contains(messageId) == false else { return }

        let memo = content.transferMemo

        // Asked of the ledger, not of the status last published: that status is written by this
        // method's own catch, so a transient chain read failing would otherwise record a permanence
        // the system never reached. The ledger only ever records work that actually happened.
        //
        // Checked before the task is registered so a settled message costs nothing at all, and an
        // unreadable ledger leaves the message for the next launch rather than deciding it.
        do {
            guard try await !isClaimTerminal(messageId: messageId, memoCoins: Set(memo.entries)) else {
                logger.debug("Skipping settled incoming coinage message=\(messageId)")
                return
            }
        } catch {
            logger.error("Cannot read claim group for \(messageId); left for next launch: \(error)")
            return
        }

        let task = Task { [coinageService, claimStatusStore, claimTransferStore, taskRegistry, logger] in
            defer { Task { await taskRegistry.remove(forMessageId: messageId) } }
            do {
                let context = try await coinageService.denominationContext()

                // Anchored to this device's first attempt, written once and reused. It used to be
                // `message.timestamp` — the *sender's* wall clock, compared against the receiver's — so
                // two devices' clocks decided the window, and a message first seen after it had already
                // elapsed registered a claim whose deadline was already past. The submission policy
                // reads that as "proven absent" on its first look and gives up terminally.
                let retryUntil = try await claimTransferStore
                    .firstAttempt(for: messageId)
                    .addingTimeInterval(CoinageConstants.claimRetryWindow)

                logger.debug("Starting processing incoming coinage message=\(messageId)")

                let detections = coinageService.claimCoinsService.claim(
                    coinKeys: memo.entries,
                    groupId: messageId,
                    retryUntil: retryUntil,
                    context: context
                )
                for try await detection in detections {
                    await claimStatusStore.updateStatus(detection.incomingStatus, forMessageId: messageId)
                }
            } catch {
                logger.error("Failed to claim coinage for \(messageId): \(error)")
                await claimStatusStore.updateStatus(.error, forMessageId: messageId)
            }
        }
        await taskRegistry.register(task, forMessageId: messageId)
    }

    func isClaimTerminal(messageId: String, memoCoins: Set<PublicKey>) async throws -> Bool {
        let entries = try await coinageService.txService.getOperationGroupStatuses(messageId)

        return Self.isClaimTerminal(entries: entries, memoCoins: memoCoins)
    }
}

extension CoinageTransferMonitor {
    /// Whether this claim is finished for good, decided from what the ledger holds — the layer that
    /// actually knows. Deliberately not derived from the published ``ClaimStatus``, which this monitor's
    /// own catch writes: a transient chain read failing would otherwise record a permanence the system
    /// never reached.
    ///
    /// Pure, so the three states it distinguishes can be exercised without a chain or a store.
    static func isClaimTerminal(entries: [CoinageTxEntry], memoCoins: Set<PublicKey>) -> Bool {
        // Nothing was ever registered — the coins were not yet visible when an earlier pass ran. There
        // is nothing to be final about, and the next launch must try again. This is the ordinary
        // late-arrival case: a sender who was offline, or a slow chain.
        guard !entries.isEmpty else { return false }

        // Something is still in flight.
        guard entries.allSatisfy({ !$0.status.isLive }) else { return false }

        // Every coin must be accounted for by a settled entry. One with no entry naming it is work the
        // claim loop still has to do, whatever the entries that do exist have settled on.
        return memoCoins.isSubset(of: entries.receivedPublicKeys())
    }
}

// MARK: - Outgoing (payment status)

private extension CoinageTransferMonitor {
    func subscribeOutgoingMessages() {
        logger.debug("Going to subscribe to outgoing messages")

        outgoingTransfersSubscription = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = messageProviderFactory.subscribeMessages(with: .outgoingLocalDeviceCoinageSendMessages())
                for try await messages in stream {
                    try Task.checkCancellation()
                    for message in messages {
                        await startOutgoing(for: message)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Coinage send subscription failed: \(error)")
            }
        }
    }

    func startOutgoing(for message: Chat.LocalMessage) async {
        guard case let .coinageSend(content) = message.content else { return }
        let messageId = message.messageId
        guard await taskRegistry.contains(messageId) == false else { return }

        let memo = content.transferMemo
        let task = Task { [coinageService, claimStatusStore, taskRegistry, logger] in
            defer { Task { await taskRegistry.remove(forMessageId: messageId) } }
            do {
                let context = try await coinageService.denominationContext()
                let statuses = coinageService.transferStatusService.subscribeStatuses(coinKeys: memo.entries)

                logger.debug("Processing transfer for message: \(messageId) entries=\(memo.entries.count)")

                for try await states in statuses {
                    logger.debug("Got statuses for messageId=\(messageId) states=\(states.count)")

                    let proposedStatus = states.outgoingStatus(context: context)

                    logger.debug("Status=\(proposedStatus) message=\(messageId)")

                    await claimStatusStore.updateStatus(
                        proposedStatus,
                        forMessageId: messageId
                    )
                    if !states.isEmpty, states.values.allSatisfy(\.status.isTerminal) { break }
                }
            } catch {
                logger.error("Send status monitoring failed for \(messageId): \(error)")
                await claimStatusStore.updateStatus(.error, forMessageId: messageId)
            }
        }
        await taskRegistry.register(task, forMessageId: messageId)
    }
}

// MARK: - Status mapping

private extension CoinageTransferDetection {
    /// Maps the received-claim detection onto the chat status. Partial claims surface via
    /// `finished(claimedAmount:)` — the extension renders the shortfall against the message total.
    var incomingStatus: ClaimStatus {
        switch self {
        case .detecting:
            .detecting
        case .claiming:
            .claiming
        case let .claimingRest(claimed):
            .partiallyClaimed(claimed: claimed)
        case let .claimed(amount, _):
            .finished(claimedAmount: amount)
        case let .claimedPartially(claimed):
            .finished(claimedAmount: claimed)
        case .notClaimed:
            .error
        }
    }
}

private extension [PublicKey: CoinageTransferState] {
    /// Aggregates per-coin Appendix-A statuses into one message-level status. Mirrors Android's
    /// `toPaymentStatus`: any coin still to be taken keeps the message at `sent`/`detecting`; once
    /// nothing is outstanding, the claimed value is final.
    func outgoingStatus(context: DenominationBreakdownContext) -> ClaimStatus {
        let states = Array(values)
        guard !states.isEmpty else { return .detecting }

        let claimed = states.filter { if case .claimed = $0.status { true } else { false } }
        let awaiting = states.filter { $0.status == .awaitingClaim }
        let outstanding = states.filter { $0.status == .awaitingClaim || $0.status == .detecting }

        if !outstanding.isEmpty {
            return awaiting.isEmpty && claimed.isEmpty ? .detecting : .sent
        }
        guard !claimed.isEmpty else { return .error }

        let amount = claimed.reduce(Balance(0)) { $0 + context.valueInPlanks(for: $1.coin.exponent) }
        return .finished(claimedAmount: amount)
    }
}

private extension Chat.LocalMessage.Content.Transfer {
    var transferMemo: TransferMemo {
        TransferMemo(entries: coinKeys, totalValue: totalValue)
    }
}

// MARK: - Active Task Registry

private actor ActiveTaskRegistry {
    private var tasks: [String: Task<Void, Never>] = [:]

    func register(_ task: Task<Void, Never>, forMessageId id: String) {
        tasks[id] = task
    }

    func remove(forMessageId id: String) {
        tasks.removeValue(forKey: id)
    }

    func contains(_ id: String) -> Bool {
        tasks[id] != nil
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
