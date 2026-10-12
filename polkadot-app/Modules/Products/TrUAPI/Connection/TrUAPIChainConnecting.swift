import Foundation

/// Host side of the core's chain-connection contract. Every connection id is one
/// independent node connection: its subscription ids, limits and lifetime belong
/// to it alone. Frames pass through unchanged, and the death of the transport is
/// reported through `chainDidClose` instead of being hidden by a reconnect.
public protocol TrUAPIChainConnecting: AnyObject, Sendable {
    /// Receives responses/termination events for all logical connections.
    var eventHandler: TrUAPIChainEventHandling? { get set }

    func connect(genesisHash: Data) -> UInt32?
    func send(connectionId: UInt32, request: String) throws
    func close(connectionId: UInt32)
    func closeAll()
}

public protocol TrUAPIChainEventHandling: AnyObject {
    func chainDidReceiveResponse(connectionId: UInt32, json: String)
    func chainDidClose(connectionId: UInt32)
}

public enum TrUAPIChainConnectionError: Error {
    case unknownConnection(UInt32)
}
