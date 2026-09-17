import Foundation
import Keystore_iOS
import os
import SubstrateSdk

/// Keychain-backed ``CoinageCurrentInstallationStoring``: the installation id as its 32 raw bytes, each
/// counter as a SCALE `UInt64` holding the next unissued item. One lock serialises every operation, so
/// the two allocators and the registrar can never create two installations or hand out one item twice.
///
/// Tags are resolved on every call: a new installation key id (a new wallet) starts a fresh page and
/// zeroed counters without any migration.
public final class CoinageKeychainInstallationStore: CoinageCurrentInstallationStoring, @unchecked Sendable {
    private let keystore: KeystoreProtocol
    private let tags: any CoinageInstallationKeychainTagProviding
    private let lock = OSAllocatedUnfairLock()

    public init(keystore: KeystoreProtocol, tags: any CoinageInstallationKeychainTagProviding) {
        self.keystore = keystore
        self.tags = tags
    }

    public func getOrCreateCurrent() throws -> CoinageInstallationId {
        try lock.withLock {
            let tag = try tags.installationTag()
            if try keystore.checkKey(for: tag) {
                return try storedInstallation(tag: tag)
            }

            let created = try CoinageInstallationId.random()
            try keystore.saveKey(created.value, with: tag)
            return created
        }
    }

    public func nextCoinItem() throws -> DerivationIndex {
        try lock.withLock { try reserveNextItem(tag: tags.coinIndexTag()) }
    }

    public func nextVoucherItem() throws -> DerivationIndex {
        try lock.withLock { try reserveNextItem(tag: tags.voucherIndexTag()) }
    }
}

private extension CoinageKeychainInstallationStore {
    func storedInstallation(tag: String) throws -> CoinageInstallationId {
        let record = try keystore.fetchKey(for: tag)
        do {
            return try CoinageInstallationId(value: record)
        } catch {
            throw CoinageKeychainInstallationStoreError.corruptedRecord(tag)
        }
    }

    func reserveNextItem(tag: String) throws -> DerivationIndex {
        let item = try storedNextItem(tag: tag) ?? 0
        guard item < DerivationIndex.max else {
            throw CoinageKeychainInstallationStoreError.counterExhausted(tag)
        }

        try keystore.saveKey((item + 1).scaleEncoded(), with: tag)
        return item
    }

    func storedNextItem(tag: String) throws -> DerivationIndex? {
        guard try keystore.checkKey(for: tag) else {
            return nil
        }

        let record = try keystore.fetchKey(for: tag)
        do {
            let decoder = try ScaleDecoder(data: record)
            let item = try DerivationIndex(scaleDecoder: decoder)
            guard decoder.remained == 0 else {
                throw CoinageKeychainInstallationStoreError.corruptedRecord(tag)
            }
            return item
        } catch {
            throw CoinageKeychainInstallationStoreError.corruptedRecord(tag)
        }
    }
}

public enum CoinageKeychainInstallationStoreError: Error, Equatable {
    case corruptedRecord(String)
    case counterExhausted(String)
}
