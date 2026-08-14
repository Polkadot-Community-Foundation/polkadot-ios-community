import Foundation
import Operation_iOS
import FirebaseCore
import FirebaseRemoteConfig
import Combine
import ChainRegistry

protocol RemoteConfigDelegate: AnyObject {
    func remoteConfig(didFinishLoading result: Result<Void, Error>)
    func remoteConfig(appVersionDidChange result: Result<String, Error>)
}

extension RemoteConfigDelegate {
    func remoteConfig(didFinishLoading _: Result<Void, Error>) {}
    func remoteConfig(appVersionDidChange _: Result<String, Error>) {}
}

final class FirebaseApplicationService: RemoteConfigManaging {
    static let shared = FirebaseApplicationService()

    // MARK: Properties

    private let remoteConfig: FirebaseRemoteConfig.RemoteConfig

    weak var delegate: (any RemoteConfigDelegate)?
    private let logger: LoggerProtocol = Logger.shared

    // MARK: Initial methods

    private init() {
        #if DEBUG
            var args = ProcessInfo.processInfo.arguments
            args.append("-FIRDebugEnabled")
            ProcessInfo.processInfo.setValue(args, forKey: "arguments")
            FirebaseConfiguration.shared.setLoggerLevel(.info)
        #else
            var args = ProcessInfo.processInfo.arguments
            args.append("-FIRDebugDisabled")
            ProcessInfo.processInfo.setValue(args, forKey: "arguments")
        #endif

        FirebaseApp.configure()
        remoteConfig = FirebaseRemoteConfig.RemoteConfig.remoteConfig()

        configurationRemoteConfigSettings()
    }

    // MARK: Public methods

    func fetchRemoteConfigValues() {
        Task {
            do {
                // Signals must be set before the first fetch or that fetch resolves the
                // config of whichever condition matches without them — for the Dev build
                // that is the production config. See `CustomSignal.all`.
                try await remoteConfig.setCustomSignals(CustomSignal.all)
                let status = try await remoteConfig.fetchAndActivate()
                handleRemoteConfigStatus(status)
            } catch {
                delegate?.remoteConfig(didFinishLoading: .failure(error))
            }
        }
    }

    func asyncWaitChainsForRemoteConfigValues() -> CompoundOperationWrapper<[RemoteChainModel]> {
        asyncWaitForRemoteConfigValues(for: .chains)
    }

    func asyncWaitXcmTransfers<T: Decodable>() -> CompoundOperationWrapper<T> {
        asyncWaitForRemoteConfigValues(for: .xcmTransfers)
    }

    func asyncWaitXcmGeneralConfig<T: Decodable>() -> CompoundOperationWrapper<T> {
        asyncWaitForRemoteConfigValues(for: .generalXcmConfig)
    }

    func asyncWaitGameResultsFallbackURL() -> CompoundOperationWrapper<URL> {
        asyncWaitForRemoteConfigValues(for: .gameResultsFallbackURL)
    }

    func asyncWaitW3sMerchants<T: Decodable>() -> CompoundOperationWrapper<T> {
        asyncWaitForRemoteConfigValues(for: .w3sMerchants)
    }

    func asyncWaitCollectiblesFallbackURL() -> CompoundOperationWrapper<URL> {
        asyncWaitForRemoteConfigValues(for: .collectiblesFallbackURL)
    }

    func syncedCollectiblesEnabled() -> Bool {
        remoteConfig[.collectiblesEnabled].boolValue
    }

    func syncedAppConfig() -> RemoteAppConfig {
        RemoteAppConfig(
            identityBackendUrl: url(for: .identityBackendUrl),
            ipfsGatewayUrl: url(for: .ipfsGatewayUrl),
            gameDashboardUrl: url(for: .gameDashboardUrl),
            dotNsResolver: dotNsResolverAddress()
        )
    }

    func asyncWaitRemoteConfig() async throws -> RemoteAppConfig {
        syncedAppConfig()
    }
}

private extension FirebaseApplicationService {
    // MARK: Private methods

    private func configurationRemoteConfigSettings() {
        let remoteConfigSettings = RemoteConfigSettings()
        remoteConfigSettings.minimumFetchInterval = .zero
        remoteConfig.configSettings = remoteConfigSettings
    }

    private func handleRemoteConfigStatus(_ status: RemoteConfigFetchAndActivateStatus) {
        defer {
            delegate?.remoteConfig(didFinishLoading: .success(()))
        }
        switch status {
        case .successFetchedFromRemote:
            logger.info("RemoteConfig fetched from remote and activated")
        case .successUsingPreFetchedData:
            logger.info("RemoteConfig activated using pre-fetched data")
        case .error:
            logger.error("Error during RemoteConfig activation")
        @unknown default:
            logger.error("Unknown status during RemoteConfig activation")
        }

        let appVersion = remoteConfig[.latestAppVersion].stringValue
        guard !appVersion.isEmpty else {
            logger.error("App version not found in RemoteConfig")
            delegate?.remoteConfig(appVersionDidChange: .failure(RemoteConfigError.versionNotFound))
            return
        }
        logger.info("Fetched latest app version: \(appVersion)")
        delegate?.remoteConfig(appVersionDidChange: .success(appVersion))
    }

    func nonEmptyString(for key: String) -> String? {
        let value = remoteConfig[key].stringValue
        return value.isEmpty ? nil : value
    }

    func url(for key: String) -> URL? {
        guard let value = nonEmptyString(for: key) else { return nil }
        return URL(string: value)
    }

    func dotNsResolverAddress() -> String? {
        let json = remoteConfig[.dotNsResolver].jsonValue as? [String: String]
        return json?["resolverContractAddress"]
    }

    func asyncWaitForRemoteConfigValues<T: Decodable>(for key: String) -> CompoundOperationWrapper<T> {
        CompoundOperationWrapper(targetOperation: AsyncClosureOperation<T>(
            operationClosure: { [weak self] closure in
                guard let self else {
                    return
                }

                let data = remoteConfig[key].dataValue
                do {
                    let models = try JSONDecoder().decode(T.self, from: data)

                    closure(.success(models))
                } catch {
                    closure(.failure(error))
                }
            },
            cancelationClosure: {}
        ))
    }
}

private extension FirebaseApplicationService {
    enum CustomSignal {
        case environment
        case buildChannel

        var key: String {
            switch self {
            case .environment:
                "environment"
            case .buildChannel:
                "build_channel"
            }
        }

        var value: FirebaseRemoteConfig.CustomSignalValue {
            switch self {
            case .environment:
                #if UNSTABLE
                    "unstable"
                #elseif NIGHTLY
                    "nightly"
                #elseif DEV
                    "dev"
                #else
                    "release"
                #endif
            case .buildChannel:
                "dev"
            }
        }

        /// The signals sent before the first fetch.
        ///
        /// The public Dev build ships under the **production** bundle id and Firebase app id
        /// (Apple bins TestFlight-only records), so no `app.id` condition can single it out —
        /// the `dev_build_ios` Remote Config condition matches on `build_channel == "dev"`
        /// instead. That signal is therefore sent by the Dev build only; adding it to
        /// production builds would change what the live App Store builds resolve.
        static var all: [String: FirebaseRemoteConfig.CustomSignalValue] {
            var signals = [CustomSignal.environment.key: CustomSignal.environment.value]

            #if DEV
                signals[CustomSignal.buildChannel.key] = CustomSignal.buildChannel.value
            #endif

            return signals
        }
    }
}

// MARK: - Constants

private extension String {
    static let latestAppVersion = "latest_ios_version"
    static let chains = "chains_v2"
    static let xcmTransfers = "cross_chain_transfers"
    static let generalXcmConfig = "xcm_general_config"
    static let gameResultsFallbackURL = "game_results_fallback_url"
    static let w3sMerchants = "w3s_merchants"
    static let collectiblesFallbackURL = "collectibles_fallback_url"
    static let collectiblesEnabled = "collectibles_enabled"
    static let identityBackendUrl = "identity_backend_url"
    static let ipfsGatewayUrl = "ipfs_gateway_url"
    static let gameDashboardUrl = "game_dashboard_url"
    static let dotNsResolver = "dot_ns_config"
}
