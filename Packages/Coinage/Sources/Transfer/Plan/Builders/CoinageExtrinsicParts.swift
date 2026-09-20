import DurableTransactions
import ExtrinsicService
import Foundation
import SDKLogger
import SubstrateSdk

/// One extrinsic declared but not yet built: the call it adds and the origin that signs it.
///
/// Every coinage transaction is declared this way, so the same declaration serves a first submission —
/// where the engine builds it during registration — and a rebuild, where the policy builds it itself.
struct CoinageExtrinsicParts {
    let builder: ExtrinsicBuilderClosure
    let origin: any ExtrinsicOriginDefining
}

extension CoinageExtrinsicParts {
    var durableRequest: DurableTxRequest {
        DurableTxRequest(builder: builder, origin: origin)
    }
}

/// Builds declared extrinsics through the engine's own batching, so a rebuild's grouping, ordering and
/// mortality handling are the ones a first attempt gets rather than a second implementation of them.
struct CoinageExtrinsicBuilding: Sendable {
    let chainId: ChainId
    let engine: any DurableTxServicing

    func build(_ parts: [CoinageExtrinsicParts]) async throws -> [ExtrinsicBuiltModel] {
        try await engine.buildExtrinsics(parts.map(\.durableRequest), chainId: chainId)
    }
}
