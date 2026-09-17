import Foundation

/// The Keychain tags the current installation and its allocation counters are stored under. The app
/// derives them from its installation key id, so the package never handles that id; a missing id
/// throws and no page is created for it.
public protocol CoinageInstallationKeychainTagProviding: Sendable {
    func installationTag() throws -> String
    func coinIndexTag() throws -> String
    func voucherIndexTag() throws -> String
}

/// The one installation new keys are allocated in, and the counters that hand out its items.
///
/// Items are never re-issued: each `next…Item` call reserves an item for good, whether or not the
/// coin or voucher built for it is ever saved, so a crash between the two costs one unused key.
public protocol CoinageCurrentInstallationStoring: Sendable {
    /// The current installation, created on first call.
    func getOrCreateCurrent() throws -> CoinageInstallationId

    func nextCoinItem() throws -> DerivationIndex

    func nextVoucherItem() throws -> DerivationIndex
}
