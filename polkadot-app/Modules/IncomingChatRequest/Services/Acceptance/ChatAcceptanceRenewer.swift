import Foundation
import FoundationExt
import Individuality

protocol ChatAcceptanceRenewing: Sendable {
    func renew() async
}

struct ChatAcceptanceRenewalDependencies {
    let store: ChatAcceptanceStoring
    let allocator: NotificationStatementAccountAllocating
    let signers: ChatAcceptanceSigning
    let statementService: ChatAcceptanceStatementServicing
    let fallback: NonPrivateSigningFallbacking
}

/// Keeps published acceptances in the store until the requester acknowledges them on the device route:
/// a fresh one-shot account each period, and a re-send when the current period's copy went missing.
final class ChatAcceptanceRenewer: @unchecked Sendable {
    static let renewalBound: TimeInterval = 7 * 86_400

    private let dependencies: ChatAcceptanceRenewalDependencies
    private let dateProvider: DateProviding
    private let issueDiagnostics: ChatAcceptanceIssueDiagnostics
    private let logger: LoggerProtocol

    init(
        dependencies: ChatAcceptanceRenewalDependencies,
        dateProvider: DateProviding,
        issueDiagnostics: ChatAcceptanceIssueDiagnostics,
        logger: LoggerProtocol
    ) {
        self.dependencies = dependencies
        self.dateProvider = dateProvider
        self.issueDiagnostics = issueDiagnostics
        self.logger = logger
    }
}

extension ChatAcceptanceRenewer: ChatAcceptanceRenewing {
    func renew() async {
        do {
            let renewable = try await unacknowledgedWithinBound(dependencies.store.sentAcceptances())

            guard !renewable.isEmpty else { return }

            let period = try await dependencies.allocator.currentPeriod()
            let stale = renewable.filter { ($0.period ?? 0) < period }
            let current = renewable.filter { ($0.period ?? 0) >= period }

            try await renewStale(stale, into: period)
            await resendMissing(current)
        } catch {
            logger.error("Chat acceptance renewal failed: \(error)")
        }
    }
}

private extension ChatAcceptanceRenewer {
    func unacknowledgedWithinBound(_ candidates: [ChatAcceptanceCandidate]) async throws -> [ChatAcceptanceCandidate] {
        let now = await dateProvider.read()
        var renewable: [ChatAcceptanceCandidate] = []

        for candidate in candidates {
            if try await dependencies.store.isAcknowledged(candidate) {
                try await dependencies.store.markAcknowledged(candidate)
                issueDiagnostics.unacknowledged.recordRecovery(for: candidate.message.messageId)
            } else if now.timeIntervalSince(Date.fromChatTimestamp(candidate.message.timestamp)) > Self.renewalBound {
                issueDiagnostics.unacknowledged.recordFailure(
                    for: candidate.message.messageId,
                    error: nil,
                    counters: [:]
                )
            } else {
                renewable.append(candidate)
            }
        }

        return renewable
    }

    func renewStale(_ stale: [ChatAcceptanceCandidate], into period: UInt32) async throws {
        guard !stale.isEmpty else { return }

        let renewals = try stale.map { candidate in
            try (candidate, dependencies.signers.signer(requestId: candidate.requestId, period: period))
        }

        let claimed = try await Set(
            dependencies.allocator.initiateAllocations(for: renewals.map(\.1.signer.accountId))
        )

        await withTaskGroup(of: Void.self) { group in
            for (candidate, signer) in renewals {
                if claimed.contains(signer.signer.accountId) {
                    group.addTask { await self.publishOnceAllocated(candidate, from: signer) }
                } else {
                    group.addTask { await self.renewWithIdentity(candidate, into: period) }
                }
            }
        }
    }

    // Prompts when the contact has no consent yet; declining fails the acceptance.
    func renewWithIdentity(_ candidate: ChatAcceptanceCandidate, into period: UInt32) async {
        let messageId = candidate.message.messageId

        do {
            let identity = try await dependencies.fallback.identitySigner(for: candidate.session)
            try await dependencies.statementService.send(candidate, signer: identity)
            try await dependencies.store.markPublished(candidate, period: period)
        } catch ChatSigningConsentError.declined {
            logger.debug("Chat acceptance \(messageId) declined to renew with the username")
            try? await dependencies.store.markFailed(candidate)
        } catch {
            logger.error("Chat acceptance \(messageId) renewal with the username failed: \(error)")
        }
    }

    func publishOnceAllocated(_ candidate: ChatAcceptanceCandidate, from signer: ChatAcceptanceSigner) async {
        let messageId = candidate.message.messageId

        do {
            try await dependencies.allocator.awaitAllocated(
                signer.signer.accountId,
                timeout: ChatRequestDeliveryAccountResolver.allocationTimeout
            )
            try await dependencies.statementService.send(candidate, signer: signer.signer)
            try await dependencies.store.markPublished(candidate, period: signer.period)
            issueDiagnostics.publishFailing.recordRecovery(for: messageId)
        } catch NotificationAllocationError.noFreeSlotInPeriod {
            await renewWithIdentity(candidate, into: signer.period)
        } catch {
            logger.error("Chat acceptance \(messageId) renewal into \(signer.period) failed: \(error)")
            issueDiagnostics.publishFailing.recordFailure(for: messageId, error: error, counters: [:])
        }
    }

    func resendMissing(_ current: [ChatAcceptanceCandidate]) async {
        for candidate in current {
            guard let period = candidate.period else { continue }

            do {
                let oneShot = try dependencies.signers.signer(requestId: candidate.requestId, period: period)
                let statementService = dependencies.statementService

                guard try await !statementService.isStored(candidate, signedBy: oneShot.signer.accountId) else {
                    continue
                }

                // With consent the period's copy may be the username-signed one.
                if let identity = try await dependencies.fallback.consentedSigner(for: candidate.session) {
                    guard try await !statementService.isStored(candidate, signedBy: identity.accountId) else {
                        continue
                    }

                    try await statementService.send(candidate, signer: identity)
                } else {
                    try await statementService.send(candidate, signer: oneShot.signer)
                }
            } catch {
                logger.error("Chat acceptance \(candidate.message.messageId) re-send failed: \(error)")
            }
        }
    }
}
