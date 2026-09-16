import Foundation
import SDKLogger

enum InstallationAssetScanError: Error, Equatable {
    /// The chain read came back with a different number of answers than keys asked about, so no answer
    /// can be tied to the key it belongs to. Failing the batch leaves the scan for the next launch;
    /// pairing them up anyway would drop or misattribute recoverable balance.
    case misalignedBatch(asked: Int, answered: Int)
}

/// Reads one batch of a previous installation's subtree from chain: the coins and vouchers that exist
/// there, keyed to the indices they were derived from.
protocol InstallationAssetScanning: Sendable {
    func scanCoins(installation: CoinageInstallationId, startIndex: UInt32, count: UInt32) async throws -> [Coin]

    func scanVouchers(installation: CoinageInstallationId, startIndex: UInt32, count: UInt32) async throws -> [Voucher]
}

final class InstallationAssetScanner: InstallationAssetScanning, @unchecked Sendable {
    private let coinKeypairFactory: any CoinKeyDeriving
    private let coinOnChainQuery: any CoinOnChainQuerying
    private let voucherOnChainQuery: any VoucherOnChainQuerying
    private let logger: (any SDKLoggerProtocol)?

    init(
        coinKeypairFactory: any CoinKeyDeriving,
        coinOnChainQuery: any CoinOnChainQuerying,
        voucherOnChainQuery: any VoucherOnChainQuerying,
        logger: (any SDKLoggerProtocol)?
    ) {
        self.coinKeypairFactory = coinKeypairFactory
        self.coinOnChainQuery = coinOnChainQuery
        self.voucherOnChainQuery = voucherOnChainQuery
        self.logger = logger
    }

    func scanCoins(installation: CoinageInstallationId, startIndex: UInt32, count: UInt32) async throws -> [Coin] {
        let indexedKeys = try Self.indices(of: installation, from: startIndex, count: count).map {
            try (index: $0, publicKey: coinKeypairFactory.derivePublicKey(index: $0))
        }
        guard !indexedKeys.isEmpty else { return [] }

        let onChain = try await coinOnChainQuery.fetchCoins(for: indexedKeys.map(\.publicKey), atBlockHash: nil)
        try Self.requireAligned(asked: indexedKeys.count, answered: onChain.count)

        return zip(indexedKeys, onChain).compactMap { key, info -> Coin? in
            guard let info else { return nil }
            // Recovered from a read that found it, so it is on chain by construction. Recovery reads value
            // and age, never where the coin has been, so its provenance stays unknown.
            return Coin(
                exponent: Int16(info.value),
                derivationIndex: key.index,
                age: info.age,
                isOnchain: true,
                publicKey: key.publicKey
            )
        }
    }

    func scanVouchers(
        installation: CoinageInstallationId,
        startIndex: UInt32,
        count: UInt32
    ) async throws -> [Voucher] {
        let indices = Self.indices(of: installation, from: startIndex, count: count)
        guard !indices.isEmpty else { return [] }

        let onChain = try await voucherOnChainQuery.fetchVouchers(for: indices)
        try Self.requireAligned(asked: indices.count, answered: onChain.count)

        return zip(indices, onChain).compactMap { index, info -> Voucher? in
            guard let info, let state = Self.recoverableState(of: info) else { return nil }
            // Recovery knows where the voucher sits, not how drained its ring is: fungibility stays zero
            // and the ceiling unfrozen until the location service reads a real one.
            return Voucher(
                exponent: info.exponent,
                derivationIndex: index,
                allocatedAt: .now,
                readyAt: .distantPast,
                remoteState: state,
                publicKey: info.publicKey
            )
        }
    }
}

private extension InstallationAssetScanner {
    static func requireAligned(asked: Int, answered: Int) throws {
        guard asked == answered else {
            throw InstallationAssetScanError.misalignedBatch(asked: asked, answered: answered)
        }
    }

    static func indices(
        of installation: CoinageInstallationId,
        from startIndex: UInt32,
        count: UInt32
    ) -> [CoinageKeyIndex] {
        (startIndex ..< startIndex + count).map { CoinageKeyIndex(installation: installation, item: $0) }
    }

    /// An unloaded voucher is spent, and a suspended one has no ring to be released from — neither is
    /// balance worth recovering. Onboarding and ring-placed vouchers are.
    static func recoverableState(of info: VoucherOnChainInfo) -> Voucher.OnChainState? {
        guard !info.isUnloaded else { return nil }
        if info.ringPosition.isOnboarding { return .onboarding }
        guard info.ringPosition.ringIndex != nil else { return nil }
        return info.onChainState
    }
}
