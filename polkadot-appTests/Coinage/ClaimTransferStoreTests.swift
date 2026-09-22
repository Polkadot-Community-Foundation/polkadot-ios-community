import Foundation
import Testing
@testable import polkadot_app

/// The receiver's claim window is anchored to when *this* device first looked, not to the sender's
/// timestamp on the wire. That only works if the anchor is written once and never moves: an anchor
/// that reset each launch would keep the window permanently open, and one that differed between two
/// racing launches would give the same payment two deadlines.
@Suite("Claim transfer store")
struct ClaimTransferStoreTests {
    @Test("the anchor is written once and reused on every later call")
    func anchorIsStable() async throws {
        let store = ClaimTransferCoreDataStore(storageFacade: UserDataStorageTestFacade())

        let first = try await store.firstAttempt(for: "m1")
        let second = try await store.firstAttempt(for: "m1")

        #expect(first == second)
    }

    @Test("a later call does not move the anchor even as the clock advances")
    func anchorDoesNotFollowTheClock() async throws {
        let clock = AdvancingClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        let store = ClaimTransferCoreDataStore(
            storageFacade: UserDataStorageTestFacade(),
            dateProvider: { clock.next() }
        )

        let first = try await store.firstAttempt(for: "m1")
        let second = try await store.firstAttempt(for: "m1")

        #expect(first == second)
        #expect(second == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("each message gets its own anchor")
    func anchorsArePerMessage() async throws {
        let clock = AdvancingClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        let store = ClaimTransferCoreDataStore(
            storageFacade: UserDataStorageTestFacade(),
            dateProvider: { clock.next() }
        )

        let first = try await store.firstAttempt(for: "m1")
        let other = try await store.firstAttempt(for: "m2")

        #expect(first != other)
    }

    /// Two launches asking at once must not split the anchor: the read and the insert are one
    /// transaction, so whichever runs second sees the row the first wrote.
    @Test("concurrent first callers agree on one anchor")
    func concurrentCallersAgree() async throws {
        let clock = AdvancingClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        let store = ClaimTransferCoreDataStore(
            storageFacade: UserDataStorageTestFacade(),
            dateProvider: { clock.next() }
        )

        async let first = store.firstAttempt(for: "m1")
        async let second = store.firstAttempt(for: "m1")

        let anchors = try await [first, second]
        #expect(anchors[0] == anchors[1])
    }
}

/// Hands out a distinct, increasing Date on each call, so a second write would be visibly different
/// from the first rather than accidentally equal.
private final class AdvancingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(start: Date) {
        current = start
    }

    func next() -> Date {
        lock.lock()
        defer { lock.unlock() }

        let value = current
        current = current.addingTimeInterval(60)
        return value
    }
}
