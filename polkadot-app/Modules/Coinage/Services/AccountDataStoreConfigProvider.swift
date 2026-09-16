import Coinage
import Foundation
import SubstrateSdk

/// The `AccountDataStore` contract address from remote config (`account_data_store_config`), or nil
/// until the payload carries one.
final class AccountDataStoreConfigProvider: AccountDataStoreConfigProviding, @unchecked Sendable {
    private static let addressSize = 20

    private let remoteConfig: @Sendable () -> RemoteAppConfig?
    private let logger: LoggerProtocol

    init(
        remoteConfig: @escaping @Sendable () -> RemoteAppConfig? = { AppConfigProvider.shared.getRemoteConfig() },
        logger: LoggerProtocol = Logger.shared
    ) {
        self.remoteConfig = remoteConfig
        self.logger = logger
    }

    func contractAddress() async -> Data? {
        guard let hex = remoteConfig()?.accountDataStoreContract else { return nil }

        // A delivered address that cannot be used is a config mistake, not a payload still on its way:
        // both stall registration, and only the log tells them apart.
        guard let address = try? Data(hexString: hex), address.count == Self.addressSize else {
            logger.error("Remote config carries an unusable AccountDataStore contract address: \(hex)")
            return nil
        }
        return address
    }
}
