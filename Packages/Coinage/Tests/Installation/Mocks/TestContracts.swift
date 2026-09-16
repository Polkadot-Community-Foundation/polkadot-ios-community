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

enum TestContracts {
    static let contract = Data(repeating: 0x0C, count: 20)
    static let otherContract = Data(repeating: 0x0D, count: 20)
}
