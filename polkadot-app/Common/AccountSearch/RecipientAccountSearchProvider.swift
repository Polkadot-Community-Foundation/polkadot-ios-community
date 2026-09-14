import Foundation
import SubstrateSdk
import SubstrateSdkExt
import AsyncExtensions
import StructuredConcurrency
import os
import Operation_iOS
import SDKLogger

final class RecipientAccountSearchProvider: AccountSearching {
    typealias RecentPayload = RecentContactModelWithUsername
    typealias MatchPayload = ContactSearchPayload

    private let recentRecipientsProvider: RecentRecipientsProvider
    private let localContactSearch: LocalContactSearching
    private let remoteContactSearch: RemoteContactOperationMaking
    private let logger: LoggerProtocol
    private let stateLock: OSAllocatedUnfairLock<State>
    private let sourcesChangedNotifier = SourcesChangedNotifier()
    private var recentTask: Task<Void, Never>?

    init(
        recentRecipientsProvider: RecentRecipientsProvider,
        localContactSearch: LocalContactSearching,
        remoteContactSearch: RemoteContactOperationMaking,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.recentRecipientsProvider = recentRecipientsProvider
        self.localContactSearch = localContactSearch
        self.remoteContactSearch = remoteContactSearch
        self.logger = logger
        stateLock = OSAllocatedUnfairLock(initialState: State())
    }

    deinit {
        recentTask?.cancel()
        sourcesChangedNotifier.finish()
    }

    func setup() {
        subscribeToRecentRecipients()
    }

    func sourcesChanged() -> AnyAsyncSequence<Void> {
        sourcesChangedNotifier.sequence()
    }

    func search(query: String?) async throws -> AccountSearchSections<RecentPayload, MatchPayload> {
        let recentRows = stateLock.withLock { $0.recentRows }

        guard let query, !query.isEmpty else {
            let localContacts = try await fetchLocalContacts(matching: nil)
            return AccountSearchComposer.compose(
                query: nil,
                recent: recentRows,
                contacts: localContacts,
                global: [],
                excluding: []
            )
        }

        let trimmed = query.trimmingDot()

        async let localResult = fetchLocalContacts(matching: trimmed)
        async let globalResult = fetchGlobalContacts(query: trimmed)

        let localContacts = try await localResult
        let globalContacts = await globalResult

        return AccountSearchComposer.compose(
            query: query,
            recent: recentRows,
            contacts: localContacts,
            global: globalContacts,
            excluding: []
        )
    }
}

private extension RecipientAccountSearchProvider {
    struct State {
        var recentRows: [SearchRow<RecentContactModelWithUsername>] = []
    }

    func subscribeToRecentRecipients() {
        recentTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await rows in recentRecipientsProvider.subscribe() {
                    guard !Task.isCancelled else { return }
                    stateLock.withLock { $0.recentRows = rows }
                    sourcesChangedNotifier.notify()
                }
            } catch {
                logger.error("Recent recipients subscription error: \(error)")
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

        return contacts.map { contact in
            SearchRow(
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
                return [makeRemoteRow(contact: account)]
            }
            let contacts = try await remoteContactSearch.search(by: query).asyncExecute()
            try Task.checkCancellation()
            return contacts.map { makeRemoteRow(contact: $0) }
        } catch {
            logger.debug("Global contact search tolerance - continuing without global results: \(error)")
            return []
        }
    }

    func makeRemoteRow(
        contact: Chat.RemoteContact
    ) -> SearchRow<ContactSearchPayload> {
        SearchRow(
            accountId: contact.accountId,
            username: Username(value: contact.username),
            matchTerms: [contact.username],
            payload: .remote(contact)
        )
    }
}
