import Foundation
import Individuality
import Testing
@testable import polkadot_app

struct ChatAccountRenewalFilterTests {
    private let activePeer = Data(repeating: 0x0A, count: 32)
    private let idlePeer = Data(repeating: 0x0B, count: 32)
    private let otherAccount = Data(repeating: 0x0C, count: 32)
    private let entropyManager = FixedRootEntropyManager()
    private let peerAccounts = ChatPeerAccounts(tldProvider: StubDotNsTldProvider(tld: "dot"))
    private let dateProvider = MockDateProvider()

    @Test func lapsesIdleChatAccountsOnly() async throws {
        let activity = StubChatActivityProvider(
            activity: ChatActivity(peers: [activePeer, idlePeer], activePeers: [activePeer])
        )
        let active = try record(for: statementAccountId(of: activePeer))
        let idle = try record(for: statementAccountId(of: idlePeer))
        let other = record(for: otherAccount)

        let renewable = try await makeFilter(activity: activity).renewable([active, idle, other])

        #expect(renewable.map(\.accountId) == [active.accountId, other.accountId])
    }

    @Test func looksBackThreeDays() async throws {
        let activity = StubChatActivityProvider(activity: ChatActivity(peers: [], activePeers: []))

        _ = try await makeFilter(activity: activity).renewable([])

        #expect(await activity.requestedCutoff == (dateProvider.read()).addingTimeInterval(-3 * 86_400))
    }
}

private extension ChatAccountRenewalFilterTests {
    func makeFilter(activity: ChatActivityProviding) -> ChatAccountRenewalFilter {
        ChatAccountRenewalFilter(
            activityProvider: activity,
            peerAccounts: peerAccounts,
            signManager: ChatSignerManager(entropyManager: entropyManager),
            dateProvider: dateProvider
        )
    }

    func statementAccountId(of peer: Data) throws -> Data {
        try ChatSignerManager(entropyManager: entropyManager)
            .makeSigner(for: peerAccounts.statementKeyId(for: peer))
            .accountId
    }

    func record(for accountId: Data) -> AllowanceRecord {
        AllowanceRecord(
            accountId: accountId,
            allocatedAt: Date(timeIntervalSince1970: 1_000),
            kind: .statementStore,
            priority: .normal,
            latestRenewedPeriod: 1
        )
    }
}
