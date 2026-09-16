import Foundation
import SubstrateSdk
import NovaCrypto
import Operation_iOS
import StructuredConcurrency

protocol VoucherAllocating: Actor {
    func allocate(exponent: Int16) async throws -> Voucher
}

/// Hands out the next voucher item in the current installation from the Keychain-backed counter, so a
/// previous installation's vouchers never move this installation's counter. The serial queue keeps
/// the reserve-then-save atomic across suspension points; a single shared instance is the only safe
/// configuration.
actor VoucherAllocator: VoucherAllocating {
    private let installationStore: any CoinageCurrentInstallationStoring
    private let delayProvider: VoucherDelayProviderProtocol
    private let voucherRepository: AnyDataProviderRepository<Voucher>
    private let keyFactory: any VoucherKeyDeriving
    private let queue = SerialOperationQueue()

    init(
        installationStore: any CoinageCurrentInstallationStoring,
        delayProvider: VoucherDelayProviderProtocol,
        voucherRepository: AnyDataProviderRepository<Voucher>,
        keyFactory: any VoucherKeyDeriving
    ) {
        self.installationStore = installationStore
        self.delayProvider = delayProvider
        self.voucherRepository = voucherRepository
        self.keyFactory = keyFactory
    }

    /// Allocates a new voucher index and persists the voucher — with its on-chain public key cached
    /// so the durability layer never re-derives it — from the moment it is minted.
    func allocate(exponent: Int16) async throws -> Voucher {
        try await queue.run { [self] in
            let index = try await nextIndex()
            let delay = delayProvider.timeInterval()
            let allocatedAt = Date.now

            let voucher = try Voucher(
                exponent: exponent,
                derivationIndex: index,
                allocatedAt: allocatedAt,
                readyAt: allocatedAt.addingTimeInterval(delay),
                publicKey: keyFactory.derivePublicKey(index: index)
            )
            try await voucherRepository.saveOperation({ [voucher] }, { [] }).asyncExecute()
            return voucher
        }
    }
}

private extension VoucherAllocator {
    func nextIndex() throws -> CoinageKeyIndex {
        let installation = try installationStore.getOrCreateCurrent()
        return try CoinageKeyIndex(installation: installation, item: installationStore.nextVoucherItem())
    }
}

protocol VoucherDelayProviderProtocol {
    func timeInterval() -> TimeInterval
}

final class VoucherDelayProvider: VoucherDelayProviderProtocol {
    private let maxWaitTime: TimeInterval = CoinageConstants.maxVoucherWaitTime

    func timeInterval() -> TimeInterval {
        TimeInterval.random(in: 0 ... maxWaitTime)
    }
}
