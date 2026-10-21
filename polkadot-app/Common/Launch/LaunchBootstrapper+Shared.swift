import Foundation
import Keystore_iOS
import KeyDerivation
import SubstrateSdk

extension LaunchBootstrapper {
    /// Shared by the root screen and a headless launch, so migrations run once per process.
    static let shared = LaunchBootstrapper(
        dependencies: LaunchBootstrapDependencies(
            migrator: makeLaunchMigrator(),
            chainRegistryClosure: { ChainRegistryFacade.sharedRegistry },
            remoteConfigManager: FirebaseFacade.shared,
            chainRegistryConfigurator: FirebaseFacade.shared,
            paymentAssetBranding: .shared,
            tldProvider: DotNsTldProviderFacade.shared,
            appliedConfigReader: { AppConfigProvider.shared.getRemoteConfig() },
            destinationResolver: makeDestinationResolver()
        ),
        clock: ContinuousClock(),
        logger: Logger.shared
    )
}

private extension LaunchBootstrapper {
    /// Local launch steps in order: erase a cross-device backup restore before any store is opened, then
    /// migrate the schemas.
    static func makeLaunchMigrator() -> Migrating {
        let restoredBackupGuard = RestoredBackupGuard(
            keyIdStore: InstallationKeyIdStore(),
            entropyManager: RootEntropyManager.shared,
            eraser: LocalStateEraser(logger: Logger.shared),
            logger: Logger.shared
        )

        let userStorageMigrator = UserStorageMigrator(
            storeURL: UserStorageParams.storageURL,
            modelDirectory: UserStorageParams.modelDirectory,
            model: UserStorageParams.modelVersion,
            fileManager: FileManager.default
        )

        let substrateStorageMigrator = SubstrateStorageMigrator(
            storeURL: SubstrateStorageParams.storageURL,
            modelDirectory: SubstrateStorageParams.modelDirectory,
            model: SubstrateStorageParams.modelVersion,
            fileManager: FileManager.default
        )

        return SerialMigrator(migrations: [restoredBackupGuard, userStorageMigrator, substrateStorageMigrator])
    }

    /// Without the theme gate, which only the UI can complete.
    static func makeDestinationResolver() -> any DecisionResolver<RootDestination> {
        SequentialDecisionResolver<RootDestination>(
            gates: [
                RootGate.Wallet(entropyManager: RootEntropyManager.shared, backupHelper: MnemonicBackupHelper()),
                RootGate.Username(usernameStorage: UsernameStorage())
            ],
            fallback: .dashboard
        )
    }
}
