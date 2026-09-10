@preconcurrency import ExtrinsicService
import Foundation
@preconcurrency import SDKLogger
import StructuredConcurrency

/// Builds and signs every request's extrinsic up-front, so each hash is known before registration.
///
/// Requests sharing one signing `origin` are built in a single `buildExtrinsics` call so their nonces
/// are sequential — required for dependent transactions where one spends another's output. Requests
/// with distinct origins are built independently, since each carries its own signer. Order is preserved
/// so the returned models align with the requests.
struct ExtrinsicBatchBuilder {
    let operationFactory: any ExtrinsicOperationFactoryProtocol
    let logger: SDKLoggerProtocol?

    func build(_ requests: [DurableTxRequest]) async throws -> [ExtrinsicBuiltModel] {
        guard !requests.isEmpty else { return [] }

        // Groups have distinct signing origins, so their builds are independent — run them concurrently
        // rather than serialising one behind another. Results are re-assembled by original request index
        // below, so the returned order is deterministic.
        let built = try await withThrowingTaskGroup(
            of: (indices: [Int], models: [ExtrinsicBuiltModel]).self
        ) { taskGroup in
            for group in groupBySharedOrigin(requests) {
                taskGroup.addTask {
                    try await (group, buildGroup(group, of: requests))
                }
            }

            var collected: [(indices: [Int], models: [ExtrinsicBuiltModel])] = []
            for try await result in taskGroup {
                collected.append(result)
            }
            return collected
        }

        var models = [ExtrinsicBuiltModel?](repeating: nil, count: requests.count)
        for entry in built {
            for (position, requestIndex) in entry.indices.enumerated() {
                models[requestIndex] = entry.models[position]
            }
        }

        return try models.map { model in
            guard let model else { throw DurableTxError.buildIncomplete }
            return model
        }
    }
}

private extension ExtrinsicBatchBuilder {
    /// Builds one same-origin group's extrinsics in a single indexed call, so their nonces are sequential.
    func buildGroup(_ group: [Int], of requests: [DurableTxRequest]) async throws -> [ExtrinsicBuiltModel] {
        logger?.debug("Building \(group.count) extrinsic(s)")
        let built = try await operationFactory.buildExtrinsics(
            { builder, index in try requests[group[index]].builder(builder) },
            origin: requests[group[0]].origin,
            payingIn: nil,
            indexes: IndexSet(0 ..< group.count)
        ).asyncExecute()

        guard built.count == group.count else {
            throw DurableTxError.buildIncomplete
        }
        return built
    }

    /// Groups request indices by the identity of their signing `origin`, preserving first-seen and
    /// within-group order. Origins are reference types, so same-instance requests — a caller reusing one
    /// origin for a dependent batch — group together; distinct instances stay separate.
    func groupBySharedOrigin(_ requests: [DurableTxRequest]) -> [[Int]] {
        var groups: [[Int]] = []
        var indexByOrigin: [ObjectIdentifier: Int] = [:]
        for (index, request) in requests.enumerated() {
            let key = ObjectIdentifier(request.origin as AnyObject)
            if let groupIndex = indexByOrigin[key] {
                groups[groupIndex].append(index)
            } else {
                indexByOrigin[key] = groups.count
                groups.append([index])
            }
        }
        return groups
    }
}
