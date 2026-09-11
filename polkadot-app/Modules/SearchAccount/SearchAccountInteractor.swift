import UIKit
import Operation_iOS
import SubstrateSdk
import SubstrateSdkExt
import ChainRegistry
import Foundation_iOS
import os
import AsyncExtensions

final class SearchAccountInteractor {
    // MARK: Properties

    weak var presenter: SearchAccountInteractorOutputProtocol?

    private let accountSearching: any AccountSearching<
        RecentContactModelWithUsername,
        ContactSearchPayload
    >
    private let chatOpenResolver: ChatOpenModelResolving
    private let debouncer = Debouncer(delay: 0.5, queue: .main)
    private var searchTask: Task<Void, Never>?
    private var setupTask: Task<Void, Never>?
    private let logger: LoggerProtocol
    private let chainAsset: ChainAsset
    private let stateLock: OSAllocatedUnfairLock<State>

    private static let maximumPrefixCount = 32

    // MARK: Initial methods

    init(
        accountSearching: any AccountSearching<
            RecentContactModelWithUsername,
            ContactSearchPayload
        >,
        chatOpenResolver: ChatOpenModelResolving,
        chainAsset: ChainAsset,
        logger: LoggerProtocol
    ) {
        self.accountSearching = accountSearching
        self.chatOpenResolver = chatOpenResolver
        self.chainAsset = chainAsset
        self.logger = logger
        stateLock = OSAllocatedUnfairLock(initialState: State(chainFormat: chainAsset.chain.chainFormat))
    }

    deinit {
        searchTask?.cancel()
        setupTask?.cancel()
    }
}

// MARK: - SearchAccountInteractorInputProtocol

extension SearchAccountInteractor: SearchAccountInteractorInputProtocol {
    func setup() {
        setupTask?.cancel()

        accountSearching.setup()
        subscribeToSourcesChanged()
    }

    func subscribeToRecentContacts() {
        // No-op: subscribeToSourcesChanged handles updates via the provider
    }

    func searchAccount(for input: String?) {
        let trimmed = input?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let query = trimmed, !query.isEmpty else {
            stateLock.withLock { $0.query = nil }
            performSearch(query: nil)
            return
        }

        let isValidAddress = (try? query.toAccountId(using: chainAsset.chain.chainFormat)) != nil

        guard isValidAddress || query.count <= Self.maximumPrefixCount else {
            stateLock.withLock { $0.query = query }
            emit(
                SearchAccountResult(
                    query: query,
                    loader: .unchanged,
                    recent: [],
                    contacts: [],
                    global: []
                )
            )
            return
        }

        stateLock.withLock { $0.query = query }

        emit(
            SearchAccountResult(
                query: query,
                loader: isValidAddress ? .unchanged : .start,
                recent: [],
                contacts: [],
                global: []
            )
        )

        guard !isValidAddress else { return }

        searchTask?.cancel()
        debouncer.debounce { [weak self] in
            self?.performSearch(query: query)
        }
    }

    func resolveChat(for address: AccountAddress) {
        guard let accountId = try? address.toAccountId(using: chainAsset.chain.chainFormat) else { return }

        let contact: Chat.RemoteContact? = stateLock.withLock { state in
            state.globalContacts[accountId]
        }

        guard let contact else { return }

        Task { [weak self, chatOpenResolver] in
            do {
                let model = try await chatOpenResolver.resolveOpenModel(for: contact)
                await self?.presenter?.didResolveChat(model)
            } catch {
                await self?.presenter?.didReceiveSearchError(message: error.localizedDescription)
            }
        }
    }
}

// MARK: - Private

private extension SearchAccountInteractor {
    func subscribeToSourcesChanged() {
        setupTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await _ in accountSearching.sourcesChanged() {
                    guard !Task.isCancelled else { return }
                    let query = stateLock.withLock { $0.query }
                    if query == nil {
                        loadIdleState()
                    } else if let query, !query.isEmpty {
                        performSearch(query: query)
                    }
                }
            } catch {
                // Subscription ended
            }
        }
    }

    func loadIdleState() {
        Task { [weak self] in
            do {
                guard let self else { return }
                let sections = try await accountSearching.search(query: nil)
                let result = SearchAccountResult(
                    query: nil,
                    loader: .unchanged,
                    recent: sections.recent.map(\.payload),
                    contacts: mapToContacts(sections.contacts),
                    global: []
                )
                await emit(result)
            } catch {
                logger.error("Load idle state failed: \(error)")
            }
        }
    }

    func performSearch(query: String?) {
        searchTask?.cancel()

        guard let query, !query.isEmpty else {
            loadIdleState()
            return
        }

        searchTask = Task { [weak self] in
            do {
                guard let self else { return }
                let sections = try await accountSearching.search(query: query)
                try Task.checkCancellation()

                let globalContacts = sections.global.compactMap { row -> (AccountId, Chat.RemoteContact)? in
                    switch row.payload {
                    case let .remote(contact, _):
                        (row.accountId, contact)
                    case .local:
                        nil
                    }
                }

                stateLock.withLock { state in
                    state.globalContacts = Dictionary(uniqueKeysWithValues: globalContacts)
                }

                let result = SearchAccountResult(
                    query: query,
                    loader: .stop,
                    recent: sections.recent.map(\.payload),
                    contacts: mapToContacts(sections.contacts),
                    global: mapToContacts(sections.global)
                )
                await emit(result)
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Search failed: \(error)")
                await self?.presenter?.didReceiveSearchError(message: error.localizedDescription)
            }
        }
    }

    func mapToContacts(_ rows: [SearchRow<ContactSearchPayload>]) -> [SearchAccountResult.Contact] {
        rows.map { row in
            SearchAccountResult.Contact(username: row.username?.value, address: row.payload.address)
        }
    }

    func emit(_ result: SearchAccountResult) {
        let isCurrent = stateLock.withLock { $0.query == result.query }

        guard isCurrent else { return }

        Task { [weak presenter] in
            await presenter?.didReceive(result)
        }
    }
}

extension SearchAccountInteractor {
    private struct State {
        let chainFormat: ChainFormat
        var query: String?
        var globalContacts: [AccountId: Chat.RemoteContact] = [:]
    }
}
