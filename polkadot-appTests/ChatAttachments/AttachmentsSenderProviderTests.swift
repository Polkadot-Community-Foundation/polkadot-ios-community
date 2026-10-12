import Foundation
import Testing
@testable import polkadot_app

struct AttachmentsSenderProviderTests {
    private let entropyManager = FixedRootEntropyManager()
    private let peerAccountId = Data(repeating: 0xAB, count: 32)

    @Test func personChatUploadsFromPerChatHopAccount() async throws {
        let wallet = try await makeProvider().getWallet(for: .person(peerAccountId))

        let expected = try account(at: ChatKeyPaths.hop(tld: "dot", peerAccountId: peerAccountId))

        #expect(try wallet.getRawPublicKey() == expected)
    }

    @Test func refusesChatWithoutContact() async {
        await #expect(throws: AttachmentsSenderProviderError.unsupportedChat) {
            try await makeProvider().getWallet(for: .chatExtension("extension", roomId: nil))
        }
    }
}

private extension AttachmentsSenderProviderTests {
    func makeProvider() -> AttachmentsSenderProvider {
        AttachmentsSenderProvider(tldProvider: StubDotNsTldProvider(tld: "dot"), entropyManager: entropyManager)
    }

    func account(at path: String) throws -> Data {
        try ChatSignerManager(entropyManager: entropyManager).makeSigner(for: path).accountId
    }
}
