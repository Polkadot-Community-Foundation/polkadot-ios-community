import Foundation

/// A coinage derivation subtree this account is known to own but did not allocate on this device: it
/// is only ever scanned for balance, and the scan progress belongs to it.
public struct PreviousInstallation: Hashable, Sendable {
    public let id: CoinageInstallationId
    public let coinScanNextIndex: UInt32
    public let voucherScanNextIndex: UInt32
    public let initialScanCompleted: Bool

    public init(
        id: CoinageInstallationId,
        coinScanNextIndex: UInt32,
        voucherScanNextIndex: UInt32,
        initialScanCompleted: Bool
    ) {
        self.id = id
        self.coinScanNextIndex = coinScanNextIndex
        self.voucherScanNextIndex = voucherScanNextIndex
        self.initialScanCompleted = initialScanCompleted
    }
}

/// The previous installations the data store lists for this account. The current one lives in the
/// Keychain (``CoinageCurrentInstallationStoring``) and is never recorded here. Implemented in the app
/// over CoreData.
public protocol CoinageInstallationRepositoryProtocol: Sendable {
    /// Records installations as previous ones, skipping any already known. Callers exclude the current
    /// installation themselves.
    func addPrevious(_ installations: [CoinageInstallationId]) async throws

    func getPrevious() async throws -> [PreviousInstallation]

    func updateCoinScanNextIndex(_ nextIndex: UInt32, for installation: CoinageInstallationId) async throws

    func updateVoucherScanNextIndex(_ nextIndex: UInt32, for installation: CoinageInstallationId) async throws

    func markInitialScanCompleted(_ installation: CoinageInstallationId) async throws
}
