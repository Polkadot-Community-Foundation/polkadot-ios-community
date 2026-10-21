import ChainRegistry
import Foundation

protocol ConnectionHold: Sendable {
    func release()
}

extension ConnectionRetainToken: ConnectionHold {}

/// The pool sleeps unretained connections on backgrounding and nothing wakes them during a background launch.
protocol BackgroundConnectionRetaining: Sendable {
    func retainAllConnections() -> any ConnectionHold
}

/// Creating the registry opens the chain store, so it is reached only after launch migrations.
struct ChainRegistryConnectionRetention: BackgroundConnectionRetaining {
    func retainAllConnections() -> any ConnectionHold {
        ChainRegistryFacade.sharedRegistry.retainConnections(.all)
    }
}
