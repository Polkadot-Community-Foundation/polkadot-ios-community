import Coinage
import Foundation
import KeyDerivation

/// Scopes the coinage Keychain items by the installation key id, the same id that scopes the root
/// entropy, so a new wallet starts a new page.
struct CoinageInstallationKeychainTags: CoinageInstallationKeychainTagProviding {
    private let keyIdStore: any InstallationKeyIdStoring

    init(keyIdStore: any InstallationKeyIdStoring) {
        self.keyIdStore = keyIdStore
    }

    func installationTag() throws -> String {
        try KeystoreTag.coinageInstallationTag(for: installationKeyId())
    }

    func coinIndexTag() throws -> String {
        try KeystoreTag.coinageCoinIndexTag(for: installationKeyId())
    }

    func voucherIndexTag() throws -> String {
        try KeystoreTag.coinageVoucherIndexTag(for: installationKeyId())
    }
}

private extension CoinageInstallationKeychainTags {
    func installationKeyId() throws -> String {
        guard let installationKeyId = keyIdStore.getInstallationKeyId() else {
            throw CoinageInstallationKeychainTagsError.missingInstallationKeyId
        }
        return installationKeyId
    }
}

enum CoinageInstallationKeychainTagsError: Error {
    case missingInstallationKeyId
}
