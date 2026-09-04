enum TabBarPanelKind: Equatable {
    case spaTabs
    case content(TabBarAction)

    var contentAction: TabBarAction? {
        guard case let .content(action) = self else {
            return nil
        }
        return action
    }
}
