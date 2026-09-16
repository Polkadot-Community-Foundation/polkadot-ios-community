import Foundation
import KeyDerivation

/// Detects a device backup restored onto another device and wipes what it carried.
///
/// The installation key id comes back with the App Group defaults, but the root entropy it indexes is a
/// this-device-only Keychain item and does not. Everything else the backup carried (both UserDefaults
/// suites; the CoreData directory is created backup-excluded by `CoreDataService`) then belongs to a
/// wallet this device cannot use, so it is erased before the migrators or the wallet gate read it. The
/// CoreData directory is removed from disk as well — no store is open yet — so the same condition reached
/// any other way still ends in a fresh install.
/// A same-device restore brings the Keychain back as well and matches nothing here. A Keychain read
/// error propagates: nothing is erased on an unknown state.
final class RestoredBackupGuard: Migrating {
    private let keyIdStore: any InstallationKeyIdStoring
    private let entropyManager: any RootEntropyManaging
    private let eraser: any LocalStateErasing
    private let logger: LoggerProtocol

    init(
        keyIdStore: any InstallationKeyIdStoring,
        entropyManager: any RootEntropyManaging,
        eraser: any LocalStateErasing,
        logger: LoggerProtocol
    ) {
        self.keyIdStore = keyIdStore
        self.entropyManager = entropyManager
        self.eraser = eraser
        self.logger = logger
    }

    func migrate() throws {
        guard keyIdStore.getInstallationKeyId() != nil else {
            return
        }

        guard try !entropyManager.hasRootEntropy() else {
            return
        }

        logger.warning("Installation key id found without root entropy: erasing state restored from a device backup")
        eraser.eraseUserDefaults()
        try eraser.eraseDatabases()
    }
}
