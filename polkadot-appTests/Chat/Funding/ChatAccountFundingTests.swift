import Clocks
import Foundation
import FoundationExt
import IssueMonitoring
import Testing
@testable import polkadot_app

@Suite(.timeLimit(.minutes(1)))
struct ChatAccountFundingTests {
    private let accountId = Data(repeating: 0x01, count: 32)
    private let funding = FakeStatementAccountFunding()
    private let dateProvider = MockDateProvider()

    @Test func skipsFundingWhileRecordCoversCurrentPeriod() async throws {
        try await funding.setRecord(period: currentPeriod())

        try await makeGate().awaitSubmittable(accountId: accountId)

        #expect(funding.calls.isEmpty)
    }

    @Test func fundsOnceWhenRecordIsStale() async throws {
        let period = try await currentPeriod()
        funding.setRecord(period: period - 1)
        funding.recordOnFund(period: period)
        let gate = makeGate()

        try await gate.awaitSubmittable(accountId: accountId)
        try await gate.awaitSubmittable(accountId: accountId)

        #expect(funding.calls.count == 1)
        #expect(funding.priorities == [.critical])
    }

    @Test func concurrentSubmissionsShareOneFunding() async throws {
        try await funding.recordOnFund(period: currentPeriod())
        let gate = makeGate()
        funding.holdNext()

        async let first: Void = gate.awaitSubmittable(accountId: accountId)
        async let second: Void = gate.awaitSubmittable(accountId: accountId)

        while funding.calls.isEmpty {
            await Task.yield()
        }
        funding.release()

        _ = try await (first, second)
        #expect(funding.calls.count == 1)
    }

    @Test func retriesWithBackoffUntilFunded() async throws {
        try await funding.recordOnFund(period: currentPeriod())
        funding.fail(times: 2)

        try await makeGate(clock: ImmediateClock()).awaitSubmittable(accountId: accountId)

        #expect(funding.calls.count == 3)
    }

    @Test func cancellationStopsRetrying() async throws {
        funding.fail(times: .max)
        let gate = makeGate()

        let submission = Task { [accountId] in try await gate.awaitSubmittable(accountId: accountId) }
        while funding.calls.isEmpty {
            await Task.yield()
        }
        submission.cancel()

        await #expect(throws: CancellationError.self) { try await submission.value }
        #expect(funding.calls.count == 1)
    }
}

private extension ChatAccountFundingTests {
    func currentPeriod() async throws -> UInt32 {
        await UInt32(dateProvider.read().timeIntervalSince1970 / .secondsInDay)
    }

    func makeGate(clock: any Clock<Duration> = ContinuousClock()) -> ChatAccountFunding {
        ChatAccountFunding(
            funding: funding,
            dateProvider: dateProvider,
            issueDiagnostics: .make(reporter: NoopIssueReporter()),
            clock: clock
        )
    }
}
