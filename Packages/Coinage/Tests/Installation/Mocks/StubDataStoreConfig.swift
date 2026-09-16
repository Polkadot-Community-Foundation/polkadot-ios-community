import AsyncExtensions
import BigInt
import DurableTransactions
import ExtrinsicService
import Foundation
import Individuality
import KeyDerivation
import os
import SubstrateSdk
@testable import Coinage

final class StubDataStoreConfig: AccountDataStoreConfigProviding, @unchecked Sendable {
    private let address = OSAllocatedUnfairLock<Data?>(initialState: nil)

    init(contract: Data? = TestContracts.contract) {
        address.withLock { $0 = contract }
    }

    var contract: Data? {
        get { address.withLock { $0 } }
        set { address.withLock { $0 = newValue } }
    }

    func contractAddress() async -> Data? { contract }
}
