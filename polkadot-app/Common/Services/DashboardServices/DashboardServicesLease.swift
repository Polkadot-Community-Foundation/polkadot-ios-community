import Foundation
import os

enum DashboardServicesDemand: Hashable {
    case interactive
    case durability
}

/// A caller's claim on the dashboard services: the dashboard holds an interactive one for its lifetime, a background
/// renewal run a durability one for the run. Releasing twice is a no-op.
final class DashboardServicesLease<Coordinator: DashboardServicesCoordinating>: @unchecked Sendable {
    let coordinator: Coordinator
    let demand: DashboardServicesDemand
    let generation: UInt64

    private let connectionHold: (any ConnectionHold)?
    private let onRelease: @MainActor (DashboardServicesLease) -> Void
    private let isReleased = OSAllocatedUnfairLock(initialState: false)

    init(
        coordinator: Coordinator,
        demand: DashboardServicesDemand,
        generation: UInt64,
        connectionHold: (any ConnectionHold)?,
        onRelease: @escaping @MainActor (DashboardServicesLease) -> Void
    ) {
        self.coordinator = coordinator
        self.demand = demand
        self.generation = generation
        self.connectionHold = connectionHold
        self.onRelease = onRelease
    }

    func release() {
        let wasReleased = isReleased.withLock { released in
            defer { released = true }
            return released
        }

        guard !wasReleased else { return }

        connectionHold?.release()
        Task { @MainActor [onRelease] in onRelease(self) }
    }
}
