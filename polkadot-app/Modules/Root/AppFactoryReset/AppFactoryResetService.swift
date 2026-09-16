#if TESTNET_FEATURE
    import Foundation
    import Kingfisher
    import Security
    import UserNotifications
    import Keystore_iOS
    import Operation_iOS
    import AlarmKit

    final class AppFactoryResetService {
        private let mnemonicBackupHelper: MnemonicBackupHelperProtocol
        private let eraser: LocalStateErasing
        private let notificationCenter: UNUserNotificationCenter
        private let logger: LoggerProtocol

        init(
            mnemonicBackupHelper: MnemonicBackupHelperProtocol,
            eraser: LocalStateErasing,
            notificationCenter: UNUserNotificationCenter = .current(),
            logger: LoggerProtocol
        ) {
            self.mnemonicBackupHelper = mnemonicBackupHelper
            self.eraser = eraser
            self.notificationCenter = notificationCenter
            self.logger = logger
        }

        func resetAllData() {
            if #available(iOS 26.0, *) {
                clearAlarmKitAlarms()
            }
            deleteAllKeychainItems()
            eraser.eraseUserDefaults()
            clearAllNotifications()
            deleteCloudBackup()
            deleteCoreDataDatabases()
            clearSDKCaches()

            logger.debug("App reset performed")
        }
    }

    private extension AppFactoryResetService {
        func deleteAllKeychainItems() {
            let classes: [CFString] = [
                kSecClassKey,
                kSecClassGenericPassword,
                kSecClassInternetPassword,
                kSecClassCertificate,
                kSecClassIdentity
            ]

            for secClass in classes {
                let query: [CFString: Any] = [kSecClass: secClass]
                let status = SecItemDelete(query as CFDictionary)
                if status != errSecSuccess, status != errSecItemNotFound {
                    logger.error("Keychain wipe failed for class \(secClass), status=\(status)")
                }
            }
        }

        @available(iOS 26.0, *)
        func clearAlarmKitAlarms() {
            guard let alarmIdString = SettingsManager.shared.string(for: .gameAlarmId),
                  let alarmId = UUID(uuidString: alarmIdString) else {
                return
            }
            do {
                try AlarmManager.shared.cancel(id: alarmId)
            } catch {
                logger.error("Failure to cancel alarm: \(error)")
            }
        }

        func clearAllNotifications() {
            notificationCenter.removeAllPendingNotificationRequests()
            notificationCenter.removeAllDeliveredNotifications()
        }

        func deleteCloudBackup() {
            do {
                try mnemonicBackupHelper.deleteMnemonic()
            } catch {
                logger.error("Failed to delete cloud backup: \(error)")
            }
        }

        // The stores are open at this point, so they go through the services rather than the eraser.
        func deleteCoreDataDatabases() {
            let stores: [(String, CoreDataServiceProtocol)] = [
                ("UserData", UserDataStorageFacade.shared.databaseService),
                ("SubstrateData", SubstrateDataStorageFacade.shared.databaseService)
            ]

            for (name, service) in stores {
                do {
                    try service.close()
                    try service.drop()
                } catch {
                    logger.error("Failed to wipe \(name): \(error)")
                }
            }
        }

        func clearSDKCaches() {
            KingfisherManager.shared.cache.clearMemoryCache()
            KingfisherManager.shared.cache.clearDiskCache()
        }
    }
#endif
