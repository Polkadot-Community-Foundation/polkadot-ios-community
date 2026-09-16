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

/// Registered installations per (contract, block hash); a read of an unlisted pair fails.
final class StubDataStoreRepository: AccountDataStoreRepositoryProtocol, @unchecked Sendable {
    struct Key: Hashable {
        let contract: Data
        let blockHash: Data?
    }

    private let lists = OSAllocatedUnfairLock<[Key: Result<Set<CoinageInstallationId>, Error>]>(initialState: [:])
    private let readCount = OSAllocatedUnfairLock(initialState: 0)
    private let registrationInput = OSAllocatedUnfairLock<Data>(initialState: Data([0xE5, 0x61, 0x86, 0x8D]))
    var account = DataStoreAccount(
        privateKey: Data(repeating: 0x0A, count: 64),
        publicKey: Data(repeating: 0x0A, count: 32),
        evmAccountId: Data(repeating: 0x0E, count: 20),
        encryptionKey: Data(repeating: 0, count: 32)
    )

    var reads: Int { readCount.withLock { $0 } }

    func listed(
        _ installations: Set<CoinageInstallationId>,
        contract: Data = TestContracts.contract,
        at blockHash: Data? = nil
    ) {
        lists.withLock { $0[Key(contract: contract, blockHash: blockHash)] = .success(installations) }
    }

    func failing(
        contract: Data = TestContracts.contract,
        at blockHash: Data? = nil,
        error: Error = InstallationStubError.unreachable
    ) {
        lists.withLock { $0[Key(contract: contract, blockHash: blockHash)] = .failure(error) }
    }

    func fetchRegisteredInstallations(contract: Data, at blockHash: Data?) async throws -> Set<CoinageInstallationId> {
        readCount.withLock { $0 += 1 }
        guard let result = lists.withLock({ $0[Key(contract: contract, blockHash: blockHash)] }) else {
            throw InstallationStubError.unreachable
        }
        return try result.get()
    }

    func registrationCall(target: InstallationRegistrationTarget) async throws -> InstallationRegistrationCall {
        InstallationRegistrationCall(
            account: account,
            contract: target.contract,
            input: registrationInput.withLock { $0 }
        )
    }
}
