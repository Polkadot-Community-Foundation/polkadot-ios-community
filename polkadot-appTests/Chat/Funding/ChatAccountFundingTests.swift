import Foundation
import IssueMonitoring
import Testing
@testable import polkadot_app

@Suite(.timeLimit(.minutes(1)))
struct ChatAccountFundingTests {
    private let accountId = Data(repeating: 0x01, count: 32)
    private let funding = FakeStatementAccountFunding()
    private let dateProvider = MockDateProvider()

    @Test func fundsAccountOncePerDay() async throws {
        let gate = makeGate()

        try await gate.awaitSubmittable(accountId: accountId)
        try await gate.awaitSubmittable(accountId: accountId)
        #expect(funding.calls.count == 1)
        #expect(funding.priorities == [.critical])

        await dateProvider.advance(by: 86_400)
        try await gate.awaitSubmittable(accountId: accountId)
        #expect(funding.calls.count == 2)
    }

    @Test func concurrentSubmissionsShareOneFunding() async throws {
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

    @Test func failsFastDuringCooldownThenRetries() async throws {
        let gate = makeGate()
        funding.fail(with: StatementAccountFundingTestError())

        await #expect(throws: StatementAccountFundingTestError.self) {
            try await gate.awaitSubmittable(accountId: accountId)
        }
        await #expect(throws: ChatAccountFundingError.recentlyFailed) {
            try await gate.awaitSubmittable(accountId: accountId)
        }
        #expect(funding.calls.count == 1)

        funding.fail(with: nil)
        await dateProvider.advance(by: 61)
        try await gate.awaitSubmittable(accountId: accountId)
        #expect(funding.calls.count == 2)
    }
}

private struct StatementAccountFundingTestError: Error {}

private extension ChatAccountFundingTests {
    func makeGate() -> ChatAccountFunding {
        ChatAccountFunding(
            funding: funding,
            dateProvider: dateProvider,
            issueDiagnostics: .make(reporter: NoopIssueReporter())
        )
    }
}
