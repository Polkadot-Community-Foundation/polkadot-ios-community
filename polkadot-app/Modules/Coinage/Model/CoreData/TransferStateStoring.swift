import Foundation

/// Writes the lifecycle row related to a chat coinage message. `CoinageTransferMonitor` is the only
/// writer; the chat message snapshot is the reader (`ChatMessageEntityMapper` attaches the row as
/// `Content.Transfer.state`).
///
/// Every write is one transaction and a no-op when the row already holds the given state, so a
/// repeated status never dirties the row, never saves, and never refreshes the message list.
protocol TransferStateStoring: Sendable {
    /// Fetch-or-insert the incoming row as `detecting`, returning when this device first tried to
    /// claim `messageId`. The anchor is written once and reused: two launches racing cannot split it,
    /// and every later call returns what the first one wrote.
    func beginIncoming(messageId: Chat.MessageId) async throws -> Date

    func updateIncoming(messageId: Chat.MessageId, state: IncomingTransferState) async throws

    func updateOutgoing(messageId: Chat.MessageId, state: OutgoingTransferState) async throws
}
