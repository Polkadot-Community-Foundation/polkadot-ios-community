import Foundation

public enum ChainSocketCloseReason: Sendable {
    case transport(Error?)
    case peerClosed
    case livenessTimeout
    case sleep
}

public protocol ChainSocketDelegate: AnyObject {
    func chainSocket(_ socket: ChainSocketProtocol, didReceive text: String)
    func chainSocket(_ socket: ChainSocketProtocol, didCloseWith reason: ChainSocketCloseReason)
}

/// One dedicated, unshared JSON-RPC WebSocket to a single chain node. Frames
/// travel verbatim in both directions; the socket owns no request ids or
/// subscription state.
///
/// Invariants:
/// - single-use: once closed it never reconnects or resends anything;
/// - inbound frames are delivered in arrival order;
/// - `didCloseWith` fires at most once, and only for closes the caller did
///   not initiate through ``close()``.
public protocol ChainSocketProtocol: AnyObject, Sendable {
    var delegate: ChainSocketDelegate? { get set }

    /// Starts the single connect attempt. Idempotent.
    func open()

    /// Buffered until connected; dropped once closed.
    func send(text: String)

    /// Caller-initiated close: no `didCloseWith` callback follows.
    func close()
}
