import Foundation
import os
import SubstrateSdk

/// The submission policies the engine knows, keyed by id. A domain registers its policies before it
/// schedules anything.
///
/// A row naming a policy that is not registered is not left waiting forever: the executor abandons it,
/// and a verdict for it is written as the failure it already was rather than deferred to a policy that
/// does not exist.
public final class DurableSubmissionPolicyRegistry: Sendable {
    private let policies = OSAllocatedUnfairLock<[SubmissionPolicyId: any DurableSubmissionPolicy]>(
        initialState: [:]
    )

    public init() {}

    public func register(_ policy: any DurableSubmissionPolicy, for id: SubmissionPolicyId) {
        policies.withLock { $0[id] = policy }
    }

    public func policy(for id: SubmissionPolicyId) -> (any DurableSubmissionPolicy)? {
        policies.withLock { $0[id] }
    }

    /// Every chain some registered policy builds for, deduplicated.
    public var chainIds: [ChainId] {
        var seen: Set<ChainId> = []
        return policies.withLock { $0.values.map(\.chainId) }
            .filter { seen.insert($0).inserted }
    }
}
