import UIKit
import AsyncExtensions
import StructuredConcurrency
import os

final class SearchContactInteractor {
    weak var presenter: SearchContactInteractorOutputProtocol?

    private let accountSearching: any AccountSearching<ContactSearchPayload, ContactSearchPayload>
    private let chatOpenResolver: ChatOpenModelResolving
    private let searchRunner = SearchRunner()
    private var searchTask: Task<Void, Never>?
    private var sourcesChangedTask: Task<Void, Never>?
    private let stateLock: OSAllocatedUnfairLock<State>

    init(
        accountSearching: any AccountSearching<ContactSearchPayload, ContactSearchPayload>,
        chatOpenResolver: ChatOpenModelResolving = ChatOpenModelResolver()
    ) {
        self.accountSearching = accountSearching
        self.chatOpenResolver = chatOpenResolver
        stateLock = OSAllocatedUnfairLock(initialState: State())
    }

    deinit {
        cancelSearchTask()
        cancelSourcesChangedTask()
    }
}

extension SearchContactInteractor: SearchContactInteractorInputProtocol {
    func setup() {
        accountSearching.setup()
        subscribeToSourcesChanged()
    }

    func search(username: String) {
        cancelSearchTask()

        guard !username.isEmpty else {
            searchTask = Task { [weak self] in
                guard !Task.isCancelled else { return }
                await self?.emitEmptyResult(for: username)
            }
            return
        }

        searchTask = Task { [weak self, weak presenter, searchRunner] in
            let stateStream = searchRunner.run {
                do {
                    return try await self?.makeSearchResult(for: username)
                } catch {
                    return nil
                }
            }
            for await state in stateStream {
                guard !Task.isCancelled else { return }
                await presenter?.didReceive(searchState: state, for: username)
            }
        }
    }

    func decide(on payload: ContactSearchPayload) {
        switch payload {
        case let .local(contact):
            Task { [weak self] in
                await self?.presenter?.didReceive(resolution: .existingChat(.person(contact.accountId)))
            }
        case let .remote(contact):
            Task { [weak self, chatOpenResolver] in
                do {
                    let openModel = try await chatOpenResolver.resolveOpenModel(for: contact)
                    await self?.presenter?.didReceive(resolution: openModel)
                } catch {
                    await self?.presenter?.didReceive(error: error)
                }
            }
        }
    }
}

private extension SearchContactInteractor {
    struct State {
        var currentQuery: String?
    }

    func subscribeToSourcesChanged() {
        sourcesChangedTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await _ in accountSearching.sourcesChanged() {
                    guard !Task.isCancelled else { return }
                    let query = stateLock.withLock { $0.currentQuery }
                    if let query, !query.isEmpty {
                        await performSearch(for: query)
                    }
                }
            } catch {
                // Subscription ended
            }
        }
    }

    func cancelSearchTask() {
        searchTask?.cancel()
        searchTask = nil
    }

    func cancelSourcesChangedTask() {
        sourcesChangedTask?.cancel()
        sourcesChangedTask = nil
    }

    @MainActor
    func emitEmptyResult(for query: String) {
        stateLock.withLock { $0.currentQuery = query }
        Task {
            do {
                let sections = try await accountSearching.search(query: nil)
                await presenter?.didReceive(
                    searchState: .result(.sections(sections)),
                    for: query
                )
            } catch {
                await presenter?.didReceive(error: error)
            }
        }
    }

    func makeSearchResult(for query: String) async -> SearchContactSearchResult? {
        do {
            stateLock.withLock { $0.currentQuery = query }
            let sections = try await accountSearching.search(query: query)
            try Task.checkCancellation()
            return .sections(sections)
        } catch {
            guard !Task.isCancelled else { return nil }
            return .error(error)
        }
    }

    @MainActor
    func performSearch(for query: String) {
        search(username: query)
    }
}
