import Foundation
import os
import ChainRegistry
import Products
import StructuredConcurrency

enum LaunchReadiness: Equatable {
    case dashboard
    case notOnboarded
    case configUnavailable
    case tldUnavailable
    case timedOut
}

protocol LaunchBootstrapping: AnyObject, Sendable {
    func start()

    func waitReady(deadline: Duration) async -> LaunchReadiness
}

struct LaunchBootstrapDependencies {
    let migrator: Migrating
    let chainRegistryClosure: ChainRegistryLazyClosure
    let remoteConfigManager: RemoteConfigManaging
    let chainRegistryConfigurator: ChainRegistryConfiguring
    let paymentAssetBranding: PaymentAssetBranding
    let tldProvider: DotNsTldProviding
    let appliedConfigReader: () -> RemoteAppConfig?
    let destinationResolver: any DecisionResolver<RootDestination>
}

final class LaunchBootstrapper {
    private static let durabilityChainIds: Set<ChainModel.Id> = [
        AppConfig.Chains.chatChain,
        AppConfig.Assets.mainAsset.chainId
    ]

    private let dependencies: LaunchBootstrapDependencies
    private let clock: any Clock<Duration>
    private let logger: LoggerProtocol
    private let didStart = OSAllocatedUnfairLock(initialState: false)

    init(dependencies: LaunchBootstrapDependencies, clock: any Clock<Duration>, logger: LoggerProtocol) {
        self.dependencies = dependencies
        self.clock = clock
        self.logger = logger
    }
}

extension LaunchBootstrapper: LaunchBootstrapping, @unchecked Sendable {
    func start() {
        let wasStarted = didStart.withLock { started in
            defer { started = true }
            return started
        }

        guard !wasStarted else { return }

        runMigrations()
        dependencies.chainRegistryConfigurator.set(chainRegistry: dependencies.chainRegistryClosure())
        dependencies.remoteConfigManager.fetchRemoteConfigValues()
        // Follows every applied config, so the logos are fetched the moment one names them.
        dependencies.paymentAssetBranding.start()
    }

    func waitReady(deadline: Duration) async -> LaunchReadiness {
        do {
            try await withTimeout(deadline, clock: clock) { [self] in
                _ = try await dependencies.remoteConfigManager.asyncWaitRemoteConfig()
                await dependencies.chainRegistryClosure().asyncWaitChainsSetup(for: Self.durabilityChainIds)
            }

            return evaluateReadiness()
        } catch {
            logger.warning("Launch readiness wait ended: \(error)")
            return dependencies.appliedConfigReader()?.isValid == true ? .timedOut : .configUnavailable
        }
    }
}

private extension LaunchBootstrapper {
    func runMigrations() {
        do {
            try dependencies.migrator.migrate()
        } catch {
            logger.error("Migration failed: \(error.localizedDescription)")
        }
    }

    func evaluateReadiness() -> LaunchReadiness {
        guard dependencies.appliedConfigReader()?.isValid == true else {
            return .configUnavailable
        }

        // Not resolved over the network here: the root screen does that on first launch.
        guard dependencies.tldProvider.currentTld() != nil else {
            return .tldUnavailable
        }

        guard (try? dependencies.destinationResolver.resolve()) == .dashboard else {
            return .notOnboarded
        }

        return .dashboard
    }
}
