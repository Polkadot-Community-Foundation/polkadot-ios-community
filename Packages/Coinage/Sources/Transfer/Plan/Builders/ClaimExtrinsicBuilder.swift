import ExtrinsicService
import Foundation
import KeyDerivation
import SDKLogger
import SubstrateSdk

/// Declares a claim of a coin a peer handed us: a `Coinage.transfer` of that coin into one of ours,
/// signed by the peer's key.
///
/// Shared by the claim path, which declares it once, and by ``ClaimRebuild``, which declares it again
/// into the coin the first attempt recorded. Minting into the same coin is what lets a payment we have
/// already made out of it keep waiting on it.
struct ClaimExtrinsicBuilder: Sendable {
    let originFactory: OriginCreating
    let extrinsics: CoinageExtrinsicBuilding

    func parts(receivedKey: Data, destination: PublicKey) throws -> CoinageExtrinsicParts {
        let call = CoinagePallet.Calls.Transfer(to: destination)
        let wallet = DynamicDerivedWallet(secretKeyProvider: { receivedKey })

        return try CoinageExtrinsicParts(
            builder: { try $0.adding(call: call.callAsFunction()) },
            origin: originFactory.createAsCoinOrigin(for: wallet)
        )
    }

    func build(_ claims: [(receivedKey: Data, destination: PublicKey)]) async throws -> [ExtrinsicBuiltModel] {
        try await extrinsics.build(claims.map { try parts(receivedKey: $0.receivedKey, destination: $0.destination) })
    }
}
