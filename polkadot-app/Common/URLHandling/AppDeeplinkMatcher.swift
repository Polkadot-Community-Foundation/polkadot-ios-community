import Foundation

protocol AppDeeplinkMatching {
    func isAppDeeplink(_ url: URL) -> Bool
}

/// Recognises links addressed to this app (any build flavor's scheme), so web content
/// can hand them to the native deep-link handler instead of loading them.
struct AppDeeplinkMatcher: AppDeeplinkMatching {
    private let isKnownScheme: (String) -> Bool

    init(isKnownScheme: @escaping (String) -> Bool = AppConfig.DeepLink.isKnownScheme) {
        self.isKnownScheme = isKnownScheme
    }

    func isAppDeeplink(_ url: URL) -> Bool {
        guard let scheme = url.scheme else {
            return false
        }

        return isKnownScheme(scheme)
    }
}
