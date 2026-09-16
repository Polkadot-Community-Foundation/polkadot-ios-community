import Foundation
import SubstrateSdk
import NovaCrypto
import KeyDerivation
import Operation_iOS
import StructuredConcurrency

protocol CoinAllocating: Actor {
    func allocate(exponent: Int16, provenance: CoinProvenance) async throws -> Coin
}

/// Hands out the next coin item in the current installation from the Keychain-backed counter, so a
/// previous installation's coins never move this installation's counter. The serial queue keeps the
/// reserve-then-save atomic across suspension points; a single shared instance is the only safe
/// configuration.
actor CoinAllocator: CoinAllocating {
    private let installationStore: any CoinageCurrentInstallationStoring
    private let coinRepository: AnyDataProviderRepository<Coin>
    private let keyFactory: any CoinKeyDeriving
    private let queue = SerialOperationQueue()

    init(
        installationStore: any CoinageCurrentInstallationStoring,
        coinRepository: AnyDataProviderRepository<Coin>,
        keyFactory: any CoinKeyDeriving
    ) {
        self.installationStore = installationStore
        self.coinRepository = coinRepository
        self.keyFactory = keyFactory
    }

    /// Allocates a new coin index and persists the coin — with its on-chain public key cached so the
    /// durability layer never re-derives it — from the moment it is minted.
    func allocate(exponent: Int16, provenance: CoinProvenance) async throws -> Coin {
        try await queue.run { [self] in
            let index = try await nextIndex()
            let coin = try Coin(
                exponent: exponent,
                derivationIndex: index,
                age: nil,
                recyclerFungibility: provenance.recyclerFungibility,
                hops: provenance.hops,
                publicKey: keyFactory.derivePublicKey(index: index)
            )
            try await coinRepository.saveOperation({ [coin] }, { [] }).asyncExecute()
            return coin
        }
    }
}

private extension CoinAllocator {
    func nextIndex() throws -> CoinageKeyIndex {
        let installation = try installationStore.getOrCreateCurrent()
        return try CoinageKeyIndex(installation: installation, item: installationStore.nextCoinItem())
    }
}
