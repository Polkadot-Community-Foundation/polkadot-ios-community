import Foundation
import os
import ChainRegistry

protocol AppSharedInitializing: AnyObject, Sendable {
    func start()

    func refetchConfig()
}

struct AppSharedInitializerDependencies {
    let migrator: Migrating
    let chainRegistryClosure: ChainRegistryLazyClosure
    let remoteConfigManager: RemoteConfigManaging
    let chainRegistryConfigurator: ChainRegistryConfiguring
}

final class AppSharedInitializer {
    private let dependencies: AppSharedInitializerDependencies
    private let logger: LoggerProtocol
    private let didStart = OSAllocatedUnfairLock(initialState: false)

    init(dependencies: AppSharedInitializerDependencies, logger: LoggerProtocol) {
        self.dependencies = dependencies
        self.logger = logger
    }
}

extension AppSharedInitializer: AppSharedInitializing, @unchecked Sendable {
    func start() {
        let wasStarted = didStart.withLock { started in
            defer { started = true }
            return started
        }

        guard !wasStarted else { return }

        runMigrations()
        dependencies.chainRegistryConfigurator.set(chainRegistry: dependencies.chainRegistryClosure())
        refetchConfig()
    }

    func refetchConfig() {
        dependencies.remoteConfigManager.fetchRemoteConfigValues()
    }
}

private extension AppSharedInitializer {
    func runMigrations() {
        do {
            try dependencies.migrator.migrate()
        } catch {
            logger.error("Migration failed: \(error.localizedDescription)")
        }
    }
}
