import Foundation
import Testing
@testable import polkadot_app

struct AttachmentsSenderProviderTests {
    private let entropyManager = FixedRootEntropyManager()

    @Test func uploadsFromSharedChatHopAccount() async throws {
        let wallet = try await makeProvider().getWallet()

        #expect(try wallet.getRawPublicKey() == account(at: ChatKeyPaths.hop(tld: "dot")))
    }
}

private extension AttachmentsSenderProviderTests {
    func makeProvider() -> AttachmentsSenderProvider {
        AttachmentsSenderProvider(
            peerAccounts: ChatPeerAccounts(tldProvider: StubDotNsTldProvider(tld: "dot")),
            entropyManager: entropyManager
        )
    }

    func account(at path: String) throws -> Data {
        try ChatSignerManager(entropyManager: entropyManager).makeSigner(for: path).accountId
    }
}
