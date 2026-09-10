import AsyncExtensions
import DurableTransactions
import Foundation

/// The scope the in-memory ledger opens for the registration hook. A domain's in-memory store recognises
/// it and writes its own rows inside; nothing needs a transaction here, so it carries no state.
public final class InMemoryRegistrationScope: DurableTxRegistrationScope {
    public init() {}
}

/// An in-memory ``DurableTxRepositoryProtocol`` with the store's guarantees: atomic batch registration
/// (a throwing hook rolls the whole batch back), monotonic sequences, the compare-and-set status write,
/// and status / group streams.
public actor InMemoryDurableTxRepository: DurableTxRepositoryProtocol {
    private var entries: [DurableTxId: DurableTxEntry] = [:]
    private var nextSequence: Int64 = 1
    private var statusObservers: [DurableTxId: [AsyncStream<DurableTxStatus>.Continuation]] = [:]
    private var groupObservers: [GroupKey: [AsyncStream<[DurableTxEntry]>.Continuation]] = [:]

    struct GroupKey: Hashable {
        let domain: TxDomainId
        let groupId: DurableTxGroupId
    }

    public init() {}

    public var allEntries: [DurableTxEntry] {
        sortedEntries
    }

    /// Test convenience: records a prepared entry keeping its id and status, assigning the next sequence.
    public func insert(_ entry: DurableTxEntry) {
        entries[entry.id] = entry.withSequence(nextSequence)
        nextSequence += 1
        notifyGroupObservers()
    }

    /// Test convenience (the production protocol has only the compare-and-set `updateTxStatus`): forces a
    /// status and notifies observers, for setting up scenarios.
    public func forceStatus(_ id: DurableTxId, to status: DurableTxStatus) throws {
        try mutate(id) { $0.withStatus(status) }
        for observer in statusObservers[id] ?? [] {
            observer.yield(status)
        }
    }

    public func register(
        _ registrations: [DurableTxRegistration],
        onRegister: @escaping DurableTxRegistrationHook
    ) async throws -> [DurableTxId] {
        let entriesSnapshot = entries
        let sequenceSnapshot = nextSequence
        do {
            var ids: [DurableTxId] = []
            for registration in registrations {
                let id = DurableTxId()
                entries[id] = registration.makeEntry(id: id, sequence: nextSequence)
                nextSequence += 1
                ids.append(id)
            }
            try onRegister(InMemoryRegistrationScope(), ids)
            notifyGroupObservers()
            return ids
        } catch {
            entries = entriesSnapshot
            nextSequence = sequenceSnapshot
            throw error
        }
    }

    @discardableResult
    public func updateTxStatus(
        for id: DurableTxId,
        expectedCurrentStatus: DurableTxStatus,
        verdict: Verdict
    ) async throws -> Bool {
        guard let current = entries[id], current.status.isLive, current.status == expectedCurrentStatus else {
            return false
        }

        let statusChanged = current.status != verdict.status
        guard statusChanged || current.successDetectedAt != verdict.successDetectedAt else { return false }

        try mutate(id) {
            $0.withStatus(verdict.status).withSuccessDetectedAt(verdict.successDetectedAt)
        }
        if statusChanged {
            for observer in statusObservers[id] ?? [] {
                observer.yield(verdict.status)
            }
        }
        return true
    }

    public func getAllEntries() async throws -> [DurableTxEntry] {
        sortedEntries
    }

    public func getEntry(id: DurableTxId) async throws -> DurableTxEntry? {
        entries[id]
    }

    public nonisolated func subscribeStatus(id: DurableTxId) -> AnyAsyncSequence<DurableTxStatus> {
        AsyncStream<DurableTxStatus> { continuation in
            Task { await self.attach(continuation, to: id) }
        }
        .eraseToAnyAsyncSequence()
    }

    public func getGroupEntries(domain: TxDomainId, groupId: DurableTxGroupId) async throws -> [DurableTxEntry] {
        sortedEntries.filter { $0.domainId == domain && $0.groupId == groupId }
    }

    public nonisolated func subscribeGroupEntries(
        domain: TxDomainId,
        groupId: DurableTxGroupId
    ) -> AnyAsyncSequence<[DurableTxEntry]> {
        AsyncStream<[DurableTxEntry]> { continuation in
            Task { await self.attachGroup(continuation, to: GroupKey(domain: domain, groupId: groupId)) }
        }
        .eraseToAnyAsyncSequence()
    }
}

private extension InMemoryDurableTxRepository {
    var sortedEntries: [DurableTxEntry] {
        entries.values.sorted { $0.sequence < $1.sequence }
    }

    func attach(_ continuation: AsyncStream<DurableTxStatus>.Continuation, to id: DurableTxId) {
        if let entry = entries[id] {
            continuation.yield(entry.status)
        }
        statusObservers[id, default: []].append(continuation)
    }

    func attachGroup(_ continuation: AsyncStream<[DurableTxEntry]>.Continuation, to key: GroupKey) {
        continuation.yield(sortedEntries.filter { $0.domainId == key.domain && $0.groupId == key.groupId })
        groupObservers[key, default: []].append(continuation)
    }

    func notifyGroupObservers() {
        for (key, observers) in groupObservers {
            let snapshot = sortedEntries.filter { $0.domainId == key.domain && $0.groupId == key.groupId }
            for observer in observers {
                observer.yield(snapshot)
            }
        }
    }

    func mutate(_ id: DurableTxId, _ transform: (DurableTxEntry) -> DurableTxEntry) throws {
        guard let entry = entries[id] else {
            throw DurableTxError.entryNotFound(id)
        }
        entries[id] = transform(entry)
        notifyGroupObservers()
    }
}
