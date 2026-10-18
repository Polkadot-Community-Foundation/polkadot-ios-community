import ChainRegistry
import Foundation

/// Something that keeps chain connections awake until released.
protocol ConnectionHold: Sendable {
    func release()
}

extension ConnectionRetainToken: ConnectionHold {}

/// Keeps chain connections awake while the app is in the background. The pool puts unretained connections to sleep on
/// backgrounding and nothing wakes them during a background launch, so a durability run must hold one.
protocol BackgroundConnectionRetaining: Sendable {
    /// Retains every connection, including ones created while held.
    func retainAllConnections() -> any ConnectionHold
}

/// Reaches the registry only when called: creating it opens the chain store, which must wait for launch migrations.
struct ChainRegistryConnectionRetention: BackgroundConnectionRetaining {
    func retainAllConnections() -> any ConnectionHold {
        ChainRegistryFacade.sharedRegistry.retainConnections(.all)
    }
}
