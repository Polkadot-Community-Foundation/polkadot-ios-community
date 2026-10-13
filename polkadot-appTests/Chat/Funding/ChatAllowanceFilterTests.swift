import Foundation
import Individuality
import Testing
@testable import polkadot_app

struct ChatAllowanceFilterTests {
    private let activePeer = Data(repeating: 0x0A, count: 32)
    private let inactivePeer = Data(repeating: 0x0B, count: 32)
    private let dateProvider = MockDateProvider()
    private let resolver = ChatStatementAccountResolver(
        peerAccounts: ChatPeerAccounts(tldProvider: StubDotNsTldProvider(tld: "dot")),
        signManager: ChatSignerManager(entropyManager: FixedRootEntropyManager())
    )

    @Test func releasesChatRecordsWithoutActivePeer() async throws {
        let active = try record(for: resolver.statementAccountId(for: activePeer), domain: .chat)
        let inactive = try record(for: resolver.statementAccountId(for: inactivePeer), domain: .chat)
        let orphan = record(for: Data(repeating: 0x0C, count: 32), domain: .chat)

        let released = try await makeFilter(activePeers: [activePeer]).recordsToRelease(from: [
            active,
            inactive,
            orphan
        ])

        #expect(released.map(\.accountId) == [inactive.accountId, orphan.accountId])
    }

    @Test func neverReleasesOtherDomains() async throws {
        let records = [AllowanceRecord.Domain.device, .product, .coinage].map { domain in
            record(for: Data(repeating: 0x0D, count: 32), domain: domain)
        }

        let released = try await makeFilter(activePeers: []).recordsToRelease(from: records)

        #expect(released.isEmpty)
    }

    @Test func looksBackThreeDays() async throws {
        let activity = StubChatActivityProvider(activePeers: [])

        _ = try await makeFilter(activity: activity).recordsToRelease(from: [
            record(for: Data(repeating: 0x0E, count: 32), domain: .chat)
        ])

        #expect(await activity.requestedCutoff == (dateProvider.read()).addingTimeInterval(-3 * 86_400))
    }
}

private extension ChatAllowanceFilterTests {
    func makeFilter(activePeers: Set<Data>) -> ChatAllowanceFilter {
        makeFilter(activity: StubChatActivityProvider(activePeers: activePeers))
    }

    func makeFilter(activity: ChatActivityProviding) -> ChatAllowanceFilter {
        ChatAllowanceFilter(activityProvider: activity, statementAccountResolver: resolver, dateProvider: dateProvider)
    }

    func record(for accountId: Data, domain: AllowanceRecord.Domain) -> AllowanceRecord {
        AllowanceRecord(
            accountId: accountId,
            allocatedAt: Date(timeIntervalSince1970: 1_000),
            kind: .statementStore,
            domain: domain,
            priority: .critical,
            latestRenewedPeriod: 1
        )
    }
}
