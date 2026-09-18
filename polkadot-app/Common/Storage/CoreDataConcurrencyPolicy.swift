import Foundation
import Operation_iOS

/// One place decides the Core Data topology per process. The extension has a 24 MB ceiling and no
/// subscriptions, so it keeps the single-context mode; the app gets the writer / observer / readers split.
enum CoreDataConcurrencyPolicy {
    static let appReaderConcurrency = 2
    static let notificationServiceExtensionSuffix = ".NotificationServiceExtension"

    static var forCurrentProcess: CoreDataConcurrencyMode {
        isNotificationServiceExtension ? .serial : .concurrent(readerConcurrency: appReaderConcurrency)
    }

    private static var isNotificationServiceExtension: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(notificationServiceExtensionSuffix) == true
    }
}
