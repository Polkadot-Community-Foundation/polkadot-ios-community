import Foundation
import Individuality
import StatementStore

protocol ChatRequestRenewing: Sendable {
    func renew() async
}

struct ChatRequestRenewalSigning {
    let allocator: NotificationStatementAccountAllocating
    let signerManager: ChatRequestSignerManaging
    let fallback: NonPrivateSigningFallbacking
}

final class ChatRequestRenewer: @unchecked Sendable {
    private static let runKey = "run"

    private let store: ChatRequestRenewalStoring
    private let allocator: NotificationStatementAccountAllocating
    private let signerManager: ChatRequestSignerManaging
    private let fallback: NonPrivateSigningFallbacking
    private let outgoingService: OutgoingChatRequestServicing
    private let diagnostics: ChatRequestDiagnostics

    init(
        store: ChatRequestRenewalStoring,
        signing: ChatRequestRenewalSigning,
        outgoingService: OutgoingChatRequestServicing,
        diagnostics: ChatRequestDiagnostics
    ) {
        self.store = store
        allocator = signing.allocator
        signerManager = signing.signerManager
        fallback = signing.fallback
        self.outgoingService = outgoingService
        self.diagnostics = diagnostics
    }
}

extension ChatRequestRenewer: ChatRequestRenewing {
    func renew() async {
        do {
            let candidates = try await store.renewalCandidates()
            let period = try await allocator.currentPeriod()
            let stale = candidates.filter { $0.period < period }
            let current = candidates.filter { $0.period >= period }

            diagnostics.logger.debug("Chat request renewal: \(stale.count) stale, \(current.count) of period \(period)")

            try await renewStale(stale, into: period)
            await resendMissing(current)
            diagnostics.issues.renewalFailing.recordRecovery(for: Self.runKey)
        } catch {
            diagnostics.logger.error("Chat request renewal failed: \(error)")
            diagnostics.issues.renewalFailing.recordFailure(for: Self.runKey, error: error, counters: [:])
        }
    }
}

private extension ChatRequestRenewer {
    func renewStale(_ stale: [ChatRequestRenewalCandidate], into period: UInt32) async throws {
        guard !stale.isEmpty else { return }

        let renewals = try stale.map { candidate in
            try (candidate, anonymousSigner(for: candidate, period: period))
        }

        let claimed = try await Set(allocator.initiateAllocations(for: renewals.map(\.1.signer.accountId)))

        let unrenewed = await withTaskGroup(of: ChatRequestRenewalCandidate?.self) { group in
            for (candidate, signer) in renewals {
                if claimed.contains(signer.signer.accountId) {
                    group.addTask {
                        await self.publishOnceAllocated(candidate, from: signer)
                        return nil
                    }
                } else {
                    group.addTask { await self.renewWithIdentity(candidate, into: period) ? nil : candidate }
                }
            }

            return await group.reduce(into: [ChatRequestRenewalCandidate]()) { unrenewed, candidate in
                if let candidate { unrenewed.append(candidate) }
            }
        }

        reportIfStarved(unrenewed, period: period)
    }

    // Prompts when the contact has no consent yet; declining fails the request.
    func renewWithIdentity(_ candidate: ChatRequestRenewalCandidate, into period: UInt32) async -> Bool {
        let requestId = candidate.message.messageId

        do {
            let identity = try await fallback.identitySigner(for: candidate.session)
            try await publish(candidate, from: ChatRequestDeliverySigner(signer: identity, period: period))
            try await store.updateAnonymousPeriod(requestId: requestId, period: period)
            return true
        } catch ChatSigningConsentError.declined {
            diagnostics.logger.debug("Chat request \(requestId) declined to renew with the username")
            try? await store.markFailed(requestId: requestId)
            return true
        } catch {
            diagnostics.logger.error("Chat request \(requestId) renewal with the username failed: \(error)")
            return false
        }
    }

    func publishOnceAllocated(_ candidate: ChatRequestRenewalCandidate, from signer: ChatRequestDeliverySigner) async {
        let requestId = candidate.message.messageId

        do {
            try await allocator.awaitAllocated(
                signer.signer.accountId,
                timeout: ChatRequestDeliveryAccountResolver.allocationTimeout
            )
        } catch NotificationAllocationError.noFreeSlotInPeriod {
            _ = await renewWithIdentity(candidate, into: signer.period)
            return
        } catch {
            diagnostics.logger.error("Chat request \(requestId) slot for \(signer.period) not claimed: \(error)")
            return
        }

        do {
            try await publish(candidate, from: signer)
            try await store.updateAnonymousPeriod(requestId: requestId, period: signer.period)
        } catch {
            diagnostics.logger.error("Chat request \(requestId) renewal into \(signer.period) failed: \(error)")
            diagnostics.issues.renewalPublishFailed.recordFailure(
                for: "\(requestId)-\(signer.period)",
                error: error,
                counters: [:]
            )
        }
    }

    func resendMissing(_ current: [ChatRequestRenewalCandidate]) async {
        for candidate in current {
            do {
                let anonymous = try anonymousSigner(for: candidate, period: candidate.period)

                guard try await !isStored(candidate, signedBy: anonymous.signer) else { continue }

                // With consent the period's copy may be the username-signed one.
                if let identity = try await fallback.consentedSigner(for: candidate.session) {
                    guard try await !isStored(candidate, signedBy: identity) else { continue }

                    try await publish(
                        candidate,
                        from: ChatRequestDeliverySigner(signer: identity, period: candidate.period)
                    )
                } else {
                    try await publish(candidate, from: anonymous)
                }
            } catch {
                diagnostics.logger.error("Chat request \(candidate.message.messageId) re-send failed: \(error)")
            }
        }
    }

    // A copy is evicted once its period and the grace window pass, so a request skipped beyond that is lost.
    func reportIfStarved(_ unclaimed: [ChatRequestRenewalCandidate], period: UInt32) {
        let starved = unclaimed.filter { $0.period + 1 < period }.count

        guard starved > 0 else { return }

        diagnostics.issues.renewalStarved.recordFailure(
            for: "\(period)",
            error: nil,
            counters: ["skipped": starved, "period": Int(period)]
        )
    }

    func anonymousSigner(
        for candidate: ChatRequestRenewalCandidate,
        period: UInt32
    ) throws -> ChatRequestDeliverySigner {
        try ChatRequestDeliverySigner(
            signer: signerManager.makeChatRequestSigner(for: candidate.message.messageId, period: period),
            period: period
        )
    }

    func isStored(
        _ candidate: ChatRequestRenewalCandidate,
        signedBy signer: StatementStoreSigning
    ) async throws -> Bool {
        try await outgoingService.isStored(
            to: candidate.session.peer,
            ownKeyId: candidate.session.own,
            signedBy: signer.accountId
        )
    }

    func publish(_ candidate: ChatRequestRenewalCandidate, from signer: ChatRequestDeliverySigner) async throws {
        try await outgoingService.send(
            message: candidate.message,
            to: candidate.session.peer,
            ownKeyId: candidate.session.own,
            signer: signer.signer
        )
    }
}
