import Foundation
import Products
import Revive
import SubstrateSdk

extension AppConfig {
    enum KnownIPFS {
        static var main: URL! {
            AppConfigProvider.shared.getRemoteConfig()!.ipfsGatewayUrl
        }
    }

    enum DotNs {
        private static var dotNsResolverAddress: String {
            AppConfigProvider.shared.getRemoteConfig()!.dotNsResolver!
        }

        /// Optional by design: an absent key disables manifest resolution and leaves legacy names
        /// working, so a value that will not decode has to degrade the same way rather than take
        /// every launch down with the rest of the config.
        private static var dotNsNameRegistryAddress: EvmAddress? {
            guard let raw = AppConfigProvider.shared.getRemoteConfig()?.dotNsNameRegistry else {
                return nil
            }

            return try? EvmAddressFormat.validate(raw.fromHex())
        }

        static let dotNsBrowse = "browse"
        /// The funding product's label: the host name of the funding page URL, falling back to the legacy
        /// `funding_domain` key while both are published.
        static var dotNsGetSome: String {
            let config = AppConfigProvider.shared.getRemoteConfig()
            return label(fromDestination: config?.fundingUrl) ?? ""
        }

        /// The offramp product's label: the host name of the withdraw page URL.
        static var dotNsOfframp: String {
            let config = AppConfigProvider.shared.getRemoteConfig()
            return label(fromDestination: config?.offrampUrl) ?? ""
        }

        /// A destination is published either as a dot-domain ("getcash.dot") or as a full URL whose
        /// host carries it ("https://getcash.dot/offramp"); the label is the name part of that host.
        private static func label(fromDestination destination: String?) -> String? {
            destination.flatMap { ProductHost.name(fromDotDomain: URL(string: $0)?.host() ?? $0) }
        }

        static let dotNsGameWebview = "game-webview"
        static let dotNsCollectibles = "collectibles-webview"

        static func config() throws -> DotNsConfig {
            let resolverAddress = try EvmAddressFormat.validate(Self.dotNsResolverAddress.fromHex())

            return DotNsConfig(
                contractsChainId: AppConfig.Chains.assethubChain,
                resolverContractAddress: resolverAddress,
                nameRegistryContractAddress: Self.dotNsNameRegistryAddress,
                ipfsGatewayBaseUrl: AppConfig.KnownIPFS.main
            )
        }
    }
}
