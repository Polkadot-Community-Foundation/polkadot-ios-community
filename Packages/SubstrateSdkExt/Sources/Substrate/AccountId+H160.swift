import Foundation
import SubstrateSdk

public extension AccountId {
    /// The H160 pallet-revive derives for a Substrate account: the last 20 bytes of `keccak256(accountId)`.
    func toH160() throws -> Data {
        try keccak256().suffix(20)
    }
}
