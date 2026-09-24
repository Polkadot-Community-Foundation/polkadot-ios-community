import BigInt
import Foundation
import SubstrateSdk

/// Raw status values shared by both transfer state rows: `claimed` and `failed` are terminal in each.
enum TransferStateStatus {
    static let firstTerminalRawValue: Int16 = 2
}

/// Lifecycle of a coinage transfer received in chat, as the durability layer reports it.
/// A partial claim is `claimed` with `actualValue` short of the message total.
struct IncomingTransferState: Equatable, Sendable {
    enum Status: Int16, Sendable {
        case detecting = 0
        case claiming = 1
        case claimed = 2
        case failed = 3

        var isTerminal: Bool { rawValue >= TransferStateStatus.firstTerminalRawValue }
    }

    let status: Status
    let actualValue: Balance?

    init(status: Status, actualValue: Balance? = nil) {
        self.status = status
        self.actualValue = actualValue
    }

    var isTerminal: Bool { status.isTerminal }
}

/// Lifecycle of a coinage transfer sent from this device, as the chain reports the peer's claims.
/// A partial claim is `claimed` with `actualValue` short of the message total.
struct OutgoingTransferState: Equatable, Sendable {
    enum Status: Int16, Sendable {
        case sending = 0
        case sent = 1
        case claimed = 2
        case failed = 3

        var isTerminal: Bool { rawValue >= TransferStateStatus.firstTerminalRawValue }
    }

    let status: Status
    let actualValue: Balance?

    init(status: Status, actualValue: Balance? = nil) {
        self.status = status
        self.actualValue = actualValue
    }

    var isTerminal: Bool { status.isTerminal }
}
