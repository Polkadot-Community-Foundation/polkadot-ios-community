import Foundation

enum SearchContactSearchResult {
    case sections(AccountSearchSections<Chat.RemoteContact, Chat.RemoteContact>)
    case error(Error)
}

typealias SearchContactSearchState = SearchRunner.State<SearchContactSearchResult>

struct SearchContactModel {
    let didFoundChat: (ChatOpenModel) -> Void
}
