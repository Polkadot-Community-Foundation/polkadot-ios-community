import Foundation
import PolkadotUI
import UIKit
import DesignSystem
import SubstrateSdk

@MainActor
final class SearchContactPresenter {
    weak var view: SearchContactViewProtocol?
    let wireframe: SearchContactWireframeProtocol
    let interactor: SearchContactInteractorInputProtocol

    private var currentSearch = CurrentSearch(
        query: "",
        state: .result(.sections(AccountSearchSections(recent: [], contacts: [], global: [])))
    )

    init(
        interactor: SearchContactInteractorInputProtocol,
        wireframe: SearchContactWireframeProtocol
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
    }
}

extension SearchContactPresenter: SearchContactPresenterProtocol {
    func setup() {
        interactor.setup()
        provideViewModel()
    }

    func search(username: String) {
        interactor.search(username: username)
    }

    func didSelectContact(identifier: String) {
        guard let contact = findContact(by: identifier) else {
            return
        }
        interactor.decide(on: contact)
    }
}

extension SearchContactPresenter: SearchContactInteractorOutputProtocol {
    func didReceive(searchState state: SearchContactSearchState, for query: String) {
        guard canApplySearchState(state, for: query) else {
            return
        }
        applySearchState(state, for: query)
    }

    func didReceive(error: any Error) {
        _ = wireframe.present(error: error, from: view)
    }

    func didReceive(resolution: ChatOpenModel) {
        wireframe.complete(from: view, with: resolution)
    }
}

private extension SearchContactPresenter {
    func canApplySearchState(_ state: SearchContactSearchState, for query: String) -> Bool {
        if case .started = state {
            return true
        }
        return query.isEmpty || currentSearch.query == query
    }

    func applySearchState(_ state: SearchContactSearchState, for query: String) {
        currentSearch = CurrentSearch(query: query, state: state)
        provideViewModel()
    }

    func provideViewModel() {
        let query = currentSearch.query
        let sections = currentSearch.sections
        let allEmpty = sections.recent.isEmpty && sections.contacts.isEmpty && sections.global.isEmpty
        let showHint = !currentSearch.isSearching && !currentSearch.queryFailed && allEmpty && query.isEmpty

        let searchFailReason: NSAttributedString?
        if !currentSearch.isSearching, currentSearch.queryFailed || (!query.isEmpty && allEmpty) {
            let searchFailedString = String(localized: .searchContactNoSuchUsername(username: query))
            var attributes = LabelStyle.title16SemiBold().attributes(for: .center)
            attributes[.foregroundColor] = UIColor.fgSecondary
            searchFailReason = NSAttributedString(
                string: searchFailedString,
                attributes: attributes
            )
        } else {
            searchFailReason = nil
        }

        let viewSections = buildViewSections(from: sections)

        let viewModel = SearchContactViewLayout.ViewModel(
            sections: viewSections,
            showHint: showHint,
            searchFailReason: searchFailReason,
            showsLoader: currentSearch.showsLoader,
            loaderText: currentSearch.loaderText
        )
        view?.didReceive(viewModel: viewModel)
    }

    func buildViewSections(
        from sections: AccountSearchSections<ContactSearchPayload, ContactSearchPayload>
    ) -> [SearchContactViewLayout.ViewModel.Section] {
        [
            makeViewSection(
                id: "recent",
                title: String(localized: .searchContactRecentChats),
                rows: sections.recent
            ),
            makeViewSection(
                id: "contacts",
                title: String(localized: .transactionSearchMyContacts),
                rows: sections.contacts
            ),
            makeViewSection(
                id: "global",
                title: String(localized: .transactionSearchAllUsers),
                rows: sections.global
            )
        ].compactMap { $0 }
    }

    func makeViewSection(
        id: String,
        title: String,
        rows: [SearchRow<ContactSearchPayload>]
    ) -> SearchContactViewLayout.ViewModel.Section? {
        guard !rows.isEmpty else { return nil }

        return SearchContactViewLayout.ViewModel.Section(
            id: id,
            title: title,
            rows: rows.map { row in
                IdentifiableContentConfiguration(
                    id: row.payload.accountId.toHex(),
                    configuration: makeListConfiguration(for: row.payload)
                )
            }
        )
    }

    func makeListConfiguration(for payload: ContactSearchPayload) -> SearchContactListConfiguration {
        let prefix = String(payload.username.prefix(1))
        let avatarViewModel = AvatarViewModel.colored(
            text: prefix,
            colorSeed: payload.accountId.toHex()
        )
        return SearchContactListConfiguration(
            userName: payload.username,
            avatarViewModel: avatarViewModel
        )
    }

    func findContact(by identifier: String) -> ContactSearchPayload? {
        let sections = currentSearch.sections
        return sections.recent.first(where: { $0.payload.accountId.toHex() == identifier })?.payload
            ?? sections.contacts.first(where: { $0.payload.accountId.toHex() == identifier })?.payload
            ?? sections.global.first(where: { $0.payload.accountId.toHex() == identifier })?.payload
    }

    struct CurrentSearch {
        let query: String
        let state: SearchContactSearchState

        var sections: AccountSearchSections<ContactSearchPayload, ContactSearchPayload> {
            guard case let .result(.sections(sections)) = state else {
                return AccountSearchSections(recent: [], contacts: [], global: [])
            }
            return sections
        }

        var queryFailed: Bool {
            guard case .result(.error) = state else {
                return false
            }
            return true
        }

        var isSearching: Bool {
            switch state {
            case .started,
                 .waiting,
                 .waitingLong:
                true
            case .result:
                false
            }
        }

        var showsLoader: Bool {
            switch state {
            case .waiting,
                 .waitingLong:
                true
            case .started,
                 .result:
                false
            }
        }

        var loaderText: String? {
            guard case .waitingLong = state else {
                return nil
            }
            return String(localized: .searchContactLoadingLong)
        }
    }
}
