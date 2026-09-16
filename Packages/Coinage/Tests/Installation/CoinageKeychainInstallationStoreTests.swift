import Foundation
import Keystore_iOS
import Testing
@testable import Coinage

struct CoinageKeychainInstallationStoreTests {
    private let keychain = InMemoryKeychain()
    private let tags = StubInstallationKeychainTags(keyId: "wallet-a")
    private let store: CoinageKeychainInstallationStore

    init() {
        store = CoinageKeychainInstallationStore(keystore: keychain, tags: tags)
    }

    @Test("the current installation is created once and read back afterwards")
    func createdOnce() throws {
        let first = try store.getOrCreateCurrent()
        let second = try store.getOrCreateCurrent()

        #expect(first == second)
        #expect(try keychain.fetchKey(for: tags.installationTag()) == first.value)
    }

    @Test("a new store over the same keychain sees the same installation and counters")
    func survivesNewInstance() throws {
        let installation = try store.getOrCreateCurrent()
        #expect(try store.nextCoinItem() == 0)
        #expect(try store.nextCoinItem() == 1)

        let reopened = CoinageKeychainInstallationStore(keystore: keychain, tags: tags)

        #expect(try reopened.getOrCreateCurrent() == installation)
        #expect(try reopened.nextCoinItem() == 2)
    }

    @Test("coin and voucher counters start at zero and advance independently")
    func independentCounters() throws {
        #expect(try store.nextCoinItem() == 0)
        #expect(try store.nextCoinItem() == 1)
        #expect(try store.nextVoucherItem() == 0)
        #expect(try store.nextCoinItem() == 2)
        #expect(try store.nextVoucherItem() == 1)
    }

    @Test("a different installation key id yields a fresh installation and zeroed counters")
    func freshPagePerKeyId() throws {
        let installation = try store.getOrCreateCurrent()
        _ = try store.nextCoinItem()

        tags.keyId = "wallet-b"

        #expect(try store.getOrCreateCurrent() != installation)
        #expect(try store.nextCoinItem() == 0)

        tags.keyId = "wallet-a"
        #expect(try store.getOrCreateCurrent() == installation)
        #expect(try store.nextCoinItem() == 1)
    }

    @Test("a missing installation key id is reported and creates nothing")
    func missingKeyId() throws {
        tags.keyId = nil

        #expect(throws: StubInstallationKeychainTags.Error.missingKeyId) { try store.getOrCreateCurrent() }
        #expect(throws: StubInstallationKeychainTags.Error.missingKeyId) { try store.nextCoinItem() }
        #expect(throws: StubInstallationKeychainTags.Error.missingKeyId) { try store.nextVoucherItem() }
    }

    @Test("a record of the wrong length is rejected instead of being read as an installation")
    func corruptedInstallation() throws {
        try keychain.saveKey(Data(repeating: 0xAB, count: 31), with: tags.installationTag())

        #expect(throws: CoinageInstallationIdError.invalidLength(31)) { try store.getOrCreateCurrent() }
    }

    @Test("an undecodable counter is reported as corrupted")
    func corruptedCounter() throws {
        try keychain.saveKey(Data([0x01]), with: tags.coinIndexTag())

        #expect(throws: try CoinageKeychainInstallationStoreError.corruptedRecord(tags.coinIndexTag())) {
            try store.nextCoinItem()
        }
    }
}

/// Tags scoped by a settable key id, mirroring the app's `KeystoreTag` layout.
final class StubInstallationKeychainTags: CoinageInstallationKeychainTagProviding, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case missingKeyId
    }

    var keyId: String?

    init(keyId: String?) {
        self.keyId = keyId
    }

    func installationTag() throws -> String { try tag("coinage.installation") }
    func coinIndexTag() throws -> String { try tag("coinage.coin.index") }
    func voucherIndexTag() throws -> String { try tag("coinage.voucher.index") }

    private func tag(_ item: String) throws -> String {
        guard let keyId else { throw Error.missingKeyId }
        return ["io.polkadotapp", keyId, item].joined(separator: ":")
    }
}
