import ExtrinsicService
import Foundation

/// One transaction to build, register and submit. A batch of these registers atomically under one
/// ``DurableTxGroupId``; requests sharing one `origin` instance are built together so their nonces are
/// sequential.
public struct DurableTxRequest {
    public let builder: ExtrinsicBuilderClosure
    public let origin: any ExtrinsicOriginDefining

    public init(builder: @escaping ExtrinsicBuilderClosure, origin: any ExtrinsicOriginDefining) {
        self.builder = builder
        self.origin = origin
    }
}

/// Failures raised by the durable transaction engine.
public enum DurableTxError: Error, Equatable {
    /// The built extrinsic is immortal, so it carries no era window to recover it against.
    case notMortal
    /// The transaction is not in the store.
    case entryNotFound(DurableTxId)
    /// A pinned chain view could not be read, so the pass cannot run.
    case chainViewUnavailable
    /// No ``TxCompletionOracle`` is registered for the domain, so the engine cannot tell which chain its
    /// transactions live on.
    case unregisteredDomain(TxDomainId)
    /// The builder returned fewer extrinsics than requested.
    case buildIncomplete
    /// A domain store was handed a registration scope opened by a different store technology.
    case foreignRegistrationScope
}
