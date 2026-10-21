import Foundation
import StatementDelivery
import Testing

@testable import polkadot_app

struct StatementDurabilityRenewalServiceTests {
    private static let requests = OutgoingStatementRenewalSummary(
        isComplete: true,
        candidates: 3,
        due: 2,
        republished: 2,
        failed: 0,
        statementsWithMissedPeriods: 1,
        missedPeriods: 1
    )

    private static let acceptances = OutgoingStatementRenewalSummary(
        isComplete: true,
        candidates: 1,
        due: 0,
        republished: 0,
        failed: 0,
        statementsWithMissedPeriods: 0,
        missedPeriods: 0
    )

    @Test func runRenewsAllowancesAndEveryStatementKind() async {
        let allowances = AllowanceSlotsRenewalSpy()
        let service = makeService(allowances: allowances)

        let report = await service.renewAll()

        #expect(allowances.callCount == 1)
        #expect(report == StatementDurabilityRenewalReport(
            chatRequests: Self.requests,
            chatAcceptances: Self.acceptances
        ))
    }

    @Test func concurrentCallersShareOneRun() async {
        let allowances = AllowanceSlotsRenewalSpy(holdsRenewal: true)
        let service = makeService(allowances: allowances)

        async let first = service.renewAll()
        async let second = service.renewAll()
        await waitUntil { allowances.callCount == 1 }
        await settle()
        allowances.releaseRenewals()

        let reports = await [first, second]

        #expect(allowances.callCount == 1)
        #expect(reports[0] == reports[1])
    }

    @Test func missedPeriodIsReportedWithCountersOnly() async {
        let missedPeriod = RecordingIssueDiagnostic()
        let service = makeService(allowances: AllowanceSlotsRenewalSpy(), missedPeriod: missedPeriod)

        await service.renewAll()

        #expect(missedPeriod.failureCount == 1)
        #expect(missedPeriod.lastCounters == ["statements": 1, "missedPeriods": 1])
    }

    @Test func runWithoutGapsResetsTheLapse() async {
        let missedPeriod = RecordingIssueDiagnostic()
        let service = makeService(
            allowances: AllowanceSlotsRenewalSpy(),
            missedPeriod: missedPeriod,
            requests: Self.acceptances
        )

        await service.renewAll()

        #expect(missedPeriod.failureCount == 0)
        #expect(missedPeriod.recoveryCount == 1)
    }

    @Test func cancelledRunIsNotHandedToTheNextCaller() async {
        let allowances = AllowanceSlotsRenewalSpy(holdsRenewal: true)
        let service = makeService(allowances: allowances)

        let expiring = Task { await service.renewAll() }
        await waitUntil { allowances.callCount == 1 }
        expiring.cancel()

        let foreground = Task { await service.renewAll() }
        await waitUntil { allowances.callCount == 2 }
        allowances.releaseRenewals()

        #expect(await expiring.value == .cancelled)
        #expect(await foreground.value.chatRequests == Self.requests)
    }
}

private extension StatementDurabilityRenewalServiceTests {
    func makeService(
        allowances: AllowanceSlotsRenewalSpy,
        missedPeriod: RecordingIssueDiagnostic = RecordingIssueDiagnostic(),
        requests: OutgoingStatementRenewalSummary = Self.requests
    ) -> StatementDurabilityRenewalService {
        StatementDurabilityRenewalService(
            allowances: allowances,
            renewers: StatementRenewerProviderStub(chatRequests: requests, chatAcceptances: Self.acceptances),
            issues: StatementRenewalIssueDiagnostics(
                chatRequestsMissedPeriod: missedPeriod,
                chatAcceptancesMissedPeriod: RecordingIssueDiagnostic()
            ),
            logger: StubLogger()
        )
    }

    func waitUntil(_ condition: () -> Bool) async {
        var turns = 0

        while !condition(), turns < 1_000 {
            await Task.yield()
            turns += 1
        }
    }

    func settle() async {
        for _ in 0 ..< 100 {
            await Task.yield()
        }
    }
}
