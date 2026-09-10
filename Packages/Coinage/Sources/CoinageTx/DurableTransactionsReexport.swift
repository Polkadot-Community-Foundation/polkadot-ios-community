/// Coinage's transactions are rows of the shared durability ledger, so callers name the engine's types
/// (`BlockRef`, `DurableTxStatus`, `ReadResult`, …) directly. Re-exported so importing `Coinage` keeps
/// every existing call site compiling.
@_exported import DurableTransactions
