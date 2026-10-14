import Foundation
import StatementStore

struct ChatAcceptanceSigner {
    let signer: StatementStoreSigning
    let period: UInt32
}

protocol ChatAcceptanceSigning {
    func signer(requestId: String, period: UInt32) throws -> ChatAcceptanceSigner
}

/// One-shot acceptance accounts: a notification slot binds an account to one period, so each period gets its own.
struct ChatAcceptanceSigners: ChatAcceptanceSigning {
    let signManager: StatementStoreSignerManaging

    func signer(requestId: String, period: UInt32) throws -> ChatAcceptanceSigner {
        let path = try ChatKeyPaths.accept(requestId: requestId, period: period)
        return try ChatAcceptanceSigner(signer: signManager.makeSigner(for: path), period: period)
    }
}
