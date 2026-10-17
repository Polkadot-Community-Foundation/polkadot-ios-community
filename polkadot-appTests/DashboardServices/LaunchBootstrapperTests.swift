import Foundation
import Testing
import ChainRegistry

@testable import polkadot_app

struct LaunchBootstrapperTests {
    @Test func launchPassRunsOnceAcrossCallers() {
        let migrator = MockMigrator()
        let bootstrapper = makeBootstrapper(migrator: migrator)

        bootstrapper.start()
        bootstrapper.start()

        #expect(migrator.migrateCallCount == 1)
    }

    @Test func readyForDashboardWhenConfigChainsTldAndUserAreInPlace() async {
        let bootstrapper = makeBootstrapper()

        let readiness = await bootstrapper.waitReady(deadline: .seconds(5))

        #expect(readiness == .dashboard)
    }

    @Test func notReadyWithoutCachedTld() async {
        let bootstrapper = makeBootstrapper(tld: nil)

        let readiness = await bootstrapper.waitReady(deadline: .seconds(5))

        #expect(readiness == .tldUnavailable)
    }

    @Test func notReadyBeforeOnboardingFinishes() async {
        let bootstrapper = makeBootstrapper(destination: .usernameCheck)

        let readiness = await bootstrapper.waitReady(deadline: .seconds(5))

        #expect(readiness == .notOnboarded)
    }

    @Test func notReadyWithoutAppliedConfig() async {
        let bootstrapper = makeBootstrapper(appliedConfig: nil)

        let readiness = await bootstrapper.waitReady(deadline: .seconds(5))

        #expect(readiness == .configUnavailable)
    }
}

private extension LaunchBootstrapperTests {
    static let validConfig = RemoteAppConfig(
        identityBackendUrl: URL(string: "https://example.com"),
        ipfsGatewayUrl: URL(string: "https://ipfs.example.com"),
        dotNsResolver: "resolver.example.com",
        dotNsNameRegistry: nil,
        coinageInstanceId: 1,
        fundingUrl: nil,
        offrampUrl: nil,
        accountDataStoreContract: nil,
        paymentAsset: nil,
        appSharingUrl: nil
    )

    func makeBootstrapper(
        migrator: MockMigrator = MockMigrator(),
        tld: String? = "dot",
        destination: RootDestination = .dashboard,
        appliedConfig: RemoteAppConfig? = Self.validConfig
    ) -> LaunchBootstrapper {
        let chainRegistry = MockChainRegistry()
        chainRegistry.chainsOnSubscribe = [
            makeChain(id: AppConfig.Chains.chatChain),
            makeChain(id: AppConfig.Assets.mainAsset.chainId)
        ]

        return LaunchBootstrapper(
            dependencies: LaunchBootstrapDependencies(
                migrator: migrator,
                chainRegistryClosure: { chainRegistry },
                remoteConfigManager: MockRemoteConfigManager(),
                chainRegistryConfigurator: MockChainRegistryConfigurator(),
                paymentAssetBranding: .shared,
                tldProvider: StubDotNsTldProvider(tld: tld),
                appliedConfigReader: { appliedConfig },
                destinationResolver: MockDecisionResolver(destination: destination)
            ),
            clock: ContinuousClock(),
            logger: StubLogger()
        )
    }

    func makeChain(id: String) -> ChainModel {
        ChainModel(
            chainId: id,
            parentId: nil,
            name: id,
            assets: [],
            nodes: [],
            nodeSwitchStrategy: .roundRobin,
            addressPrefix: 0,
            explicitGenesisHash: nil,
            types: nil,
            icon: nil,
            options: nil,
            externalApis: nil,
            explorers: nil,
            order: 0,
            additional: nil,
            syncMode: .full
        )
    }
}
