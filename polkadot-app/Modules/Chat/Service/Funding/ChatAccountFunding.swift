import Foundation
import FoundationExt
import Individuality
import MessageExchangeKit
import os
import SubstrateSdk

/// Funds a chat statement account before it submits.
final class ChatAccountFunding: @unchecked Sendable {
    private struct State {
        var fundedDay: [AccountId: Int] = [:]
        var failedAt: [AccountId: Date] = [:]
        var inFlight: [AccountId: Task<Void, Error>] = [:]
    }

    private let funding: StatementAccountFunding
    private let dateProvider: DateProviding
    private let issueDiagnostics: ChatAccountFundingIssueDiagnostics
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(
        funding: StatementAccountFunding,
        dateProvider: DateProviding,
        issueDiagnostics: ChatAccountFundingIssueDiagnostics
    ) {
        self.funding = funding
        self.dateProvider = dateProvider
        self.issueDiagnostics = issueDiagnostics
    }
}

extension ChatAccountFunding: PeerSessionSubmissionGating {
    func awaitSubmittable(accountId: AccountId) async throws {
        let now = await dateProvider.read()

        try await fundingTask(for: accountId, now: now)?.value
    }
}

private extension ChatAccountFunding {
    static let failureCooldown: TimeInterval = 60

    // A slot outlives its day by the grace window, so one check per day is enough.
    static func day(of date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 86_400)
    }

    func fundingTask(for accountId: AccountId, now: Date) throws -> Task<Void, Error>? {
        try state.withLock { state in
            if state.fundedDay[accountId] == Self.day(of: now) {
                return nil
            }

            if let failedAt = state.failedAt[accountId], now.timeIntervalSince(failedAt) < Self.failureCooldown {
                throw ChatAccountFundingError.recentlyFailed
            }

            if let existing = state.inFlight[accountId] {
                return existing
            }

            let task = Task { try await fund(accountId, day: Self.day(of: now), now: now) }
            state.inFlight[accountId] = task
            return task
        }
    }

    func fund(_ accountId: AccountId, day: Int, now: Date) async throws {
        do {
            try await funding.ensureFunded(accountId: accountId, priority: .critical)

            state.withLock { state in
                state.fundedDay[accountId] = day
                state.failedAt[accountId] = nil
                state.inFlight[accountId] = nil
            }

            issueDiagnostics.fundingFailing.recordRecovery(for: accountId.toHex())
        } catch {
            state.withLock { state in
                state.failedAt[accountId] = now
                state.inFlight[accountId] = nil
            }

            issueDiagnostics.fundingFailing.recordFailure(for: accountId.toHex(), error: error, counters: [:])
            throw error
        }
    }
}

enum ChatAccountFundingError: Error, Equatable {
    case recentlyFailed
}
