import Foundation
import SubstrateSdk
import AsyncExtensions
import StructuredConcurrency
import os
import Operation_iOS
import SDKLogger

final class ChatAccountSearchProvider: AccountSearching {
    typealias RecentPayload = ContactSearchPayload
    typealias MatchPayload = ContactSearchPayload

    private let recentChatsProvider: RecentChatsProvider
    private let localContactSearch: LocalContactSearching
    private let remoteContactSearch: RemoteContactOperationMaking
    private let ownAccountId: AccountId
    private let logger: LoggerProtocol
    private let stateLock: OSAllocatedUnfairLock<State>
    private let sourcesChangedNotifier = SourcesChangedNotifier()
    private var recentChatsTask: Task<Void, Never>?

    init(
        recentChatsProvider: RecentChatsProvider,
        localContactSearch: LocalContactSearching,
        remoteContactSearch: RemoteContactOperationMaking,
        ownAccountId: AccountId,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.recentChatsProvider = recentChatsProvider
        self.localContactSearch = localContactSearch
        self.remoteContactSearch = remoteContactSearch
        self.ownAccountId = ownAccountId
        self.logger = logger
        stateLock = OSAllocatedUnfairLock(initialState: State())
    }

    deinit {
        recentChatsTask?.cancel()
        sourcesChangedNotifier.finish()
    }

    func setup() {
        subscribeToRecentChats()
    }

    func sourcesChanged() -> AnyAsyncSequence<Void> {
        sourcesChangedNotifier.sequence()
    }

    func search(query: String?) async throws -> AccountSearchSections<RecentPayload, MatchPayload> {
        let recentChats = stateLock.withLock { $0.recentChats }
        let excluding = Set([ownAccountId])

        guard let query, !query.isEmpty else {
            let localContacts = try await fetchLocalContacts(matching: nil)
            return AccountSearchComposer.compose(
                query: query,
                recent: recentChats,
                contacts: localContacts,
                global: [],
                excluding: excluding
            )
        }

        async let localResult = fetchLocalContacts(matching: query)
        async let globalResult = fetchGlobalContacts(query: query)

        let localContacts = try await localResult
        let globalContacts = await globalResult

        return AccountSearchComposer.compose(
            query: query,
            recent: recentChats,
            contacts: localContacts,
            global: globalContacts,
            excluding: excluding
        )
    }
}

private extension ChatAccountSearchProvider {
    struct State {
        var recentChats: [SearchRow<ContactSearchPayload>] = []
    }

    func subscribeToRecentChats() {
        recentChatsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await chats in recentChatsProvider.subscribe() {
                    guard !Task.isCancelled else { return }
                    stateLock.withLock { $0.recentChats = chats }
                    sourcesChangedNotifier.notify()
                }
            } catch {
                logger.error("Recent chats subscription error: \(error)")
            }
        }
    }

    /// A nil prefix fetches every stored contact, otherwise only the ones whose username matches it.
    func fetchLocalContacts(matching usernamePrefix: String?) async throws -> [SearchRow<ContactSearchPayload>] {
        let repository =
            if let usernamePrefix {
                localContactSearch.searchContacts(usernamePrefix: usernamePrefix)
            } else {
                localContactSearch.allContacts()
            }

        let contacts = try await repository
            .fetchAllOperation(with: RepositoryFetchOptions())
            .asyncExecute()

        return contacts.compactMap { contact -> SearchRow<ContactSearchPayload>? in
            guard !contact.isBlocked else {
                logger.debug("Dropped blocked contact: \(contact.username)")
                return nil
            }
            return SearchRow(
                accountId: contact.accountId,
                username: Username(value: contact.username),
                matchTerms: [contact.username],
                payload: .local(contact)
            )
        }
    }

    func fetchGlobalContacts(query: String) async -> [SearchRow<ContactSearchPayload>] {
        do {
            if let accountId = try? query.toAccountId(),
               let account = try? await remoteContactSearch.fetch(by: accountId) {
                try Task.checkCancellation()
                return [makeRow(contact: account)]
            }
            let contacts = try await remoteContactSearch.search(by: query).asyncExecute()
            try Task.checkCancellation()
            return contacts.map { makeRow(contact: $0) }
        } catch {
            logger.debug("Global contact search tolerance - continuing without global results: \(error)")
            return []
        }
    }

    func makeRow(contact: Chat.RemoteContact) -> SearchRow<ContactSearchPayload> {
        SearchRow(
            accountId: contact.accountId,
            username: Username(value: contact.username),
            matchTerms: [contact.username],
            payload: .remote(contact)
        )
    }
}
