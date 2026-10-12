import Foundation
import SubstrateSdk

public protocol AllowanceSlotAllocating {
    /// Returns the period the slot was allocated into
    @discardableResult
    func assignSlot(accountId: AccountId, priority: AllowanceRecord.Priority) async throws -> UInt32

    /// Fails instead of taking another account's slot when `allowsEviction` is false.
    @discardableResult
    func assignSlot(
        accountId: AccountId,
        priority: AllowanceRecord.Priority,
        allowsEviction: Bool
    ) async throws -> UInt32
}

public extension AllowanceSlotAllocating {
    func assignSlot(
        accountId: AccountId,
        priority: AllowanceRecord.Priority,
        allowsEviction _: Bool
    ) async throws -> UInt32 {
        try await assignSlot(accountId: accountId, priority: priority)
    }
}

public enum AllowanceSlotAssignmentError: Error {
    case noSlotsAvailable
}
