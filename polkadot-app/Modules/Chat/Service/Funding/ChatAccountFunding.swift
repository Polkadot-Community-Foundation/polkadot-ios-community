import Foundation
import FoundationExt
import Individuality
import MessageExchangeKit
import os
import SubstrateSdk

/// Funds a chat statement account before it submits, retrying with backoff until the account is funded.
final class ChatAccountFunding: @unchecked Sendable {
    private struct State {
        var consecutiveFailures: [AccountId: Int] = [:]
        var inFlight: [AccountId: Task<Void, Error>] = [:]
    }

    private static let firstRetryDelay: Duration = .seconds(2)
    private static let maxRetryDelay: Duration = .seconds(5 * 60)
    private static let maxBackoffDoublings = 8

    private let funding: StatementAccountFunding
    private let dateProvider: DateProviding
    private let clock: any Clock<Duration>
    private let issueDiagnostics: ChatAccountFundingIssueDiagnostics
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(
        funding: StatementAccountFunding,
        dateProvider: DateProviding,
        issueDiagnostics: ChatAccountFundingIssueDiagnostics,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.funding = funding
        self.dateProvider = dateProvider
        self.issueDiagnostics = issueDiagnostics
        self.clock = clock
    }
}

extension ChatAccountFunding: PeerSessionSubmissionGating {
    func awaitSubmittable(accountId: AccountId) async throws {
        while try await !isFundedForCurrentPeriod(accountId) {
            do {
                try await fundingTask(for: accountId).value
                return
            } catch {
                try await clock.sleep(for: retryDelay(for: accountId))
            }
        }
    }
}

private extension ChatAccountFunding {
    // Same period arithmetic as the allocator: one-day periods on the device clock.
    func isFundedForCurrentPeriod(_ accountId: AccountId) async throws -> Bool {
        let period = await UInt32(dateProvider.read().timeIntervalSince1970 / .secondsInDay)
        return try await funding.hasAllocation(accountId: accountId, coveringPeriod: period)
    }

    func fundingTask(for accountId: AccountId) -> Task<Void, Error> {
        state.withLock { state in
            if let existing = state.inFlight[accountId] {
                return existing
            }

            let task = Task { try await fund(accountId) }
            state.inFlight[accountId] = task
            return task
        }
    }

    func fund(_ accountId: AccountId) async throws {
        do {
            try await funding.ensureFunded(accountId: accountId, priority: .critical, domain: .chat)

            state.withLock { state in
                state.consecutiveFailures[accountId] = nil
                state.inFlight[accountId] = nil
            }

            issueDiagnostics.fundingFailing.recordRecovery(for: accountId.toHex())
        } catch {
            state.withLock { state in
                state.consecutiveFailures[accountId, default: 0] += 1
                state.inFlight[accountId] = nil
            }

            issueDiagnostics.fundingFailing.recordFailure(for: accountId.toHex(), error: error, counters: [:])
            throw error
        }
    }

    func retryDelay(for accountId: AccountId) -> Duration {
        let failures = state.withLock { $0.consecutiveFailures[accountId] ?? 1 }
        let doublings = min(max(failures - 1, 0), Self.maxBackoffDoublings)
        return min(Self.firstRetryDelay * (1 << doublings), Self.maxRetryDelay)
    }
}
