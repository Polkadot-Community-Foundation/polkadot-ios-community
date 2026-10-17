import Foundation

protocol DashboardServicesCoordinatorMaking<Coordinator> {
    associatedtype Coordinator: DashboardServicesCoordinating

    @MainActor func makeCoordinator() -> Coordinator?
}

/// The single owner of the dashboard's service coordinator. The dashboard and a background renewal run each take a
/// lease; the coordinator runs what the live leases need and is stopped and dropped once none are left, so a stopped
/// instance is never started again.
@MainActor
final class DashboardServicesManager<Coordinator: DashboardServicesCoordinating> {
    private let bootstrapper: LaunchBootstrapping
    private let coordinatorFactory: any DashboardServicesCoordinatorMaking<Coordinator>
    private let headlessBootDeadline: Duration
    private let logger: LoggerProtocol

    private var coordinator: Coordinator?
    private var generation: UInt64 = 0
    private var leaseCounts: [DashboardServicesDemand: Int] = [:]
    private var headlessBoot: Task<Coordinator?, Never>?

    init(
        bootstrapper: LaunchBootstrapping,
        coordinatorFactory: any DashboardServicesCoordinatorMaking<Coordinator>,
        headlessBootDeadline: Duration,
        logger: LoggerProtocol
    ) {
        self.bootstrapper = bootstrapper
        self.coordinatorFactory = coordinatorFactory
        self.headlessBootDeadline = headlessBootDeadline
        self.logger = logger
    }

    /// Creates the coordinator on first use and starts its interactive part for the first interactive lease.
    func acquireInteractive() -> DashboardServicesLease<Coordinator>? {
        guard let coordinator = existingOrNewCoordinator() else { return nil }

        if leaseCount(for: .interactive) == 0 {
            coordinator.startInteractive()
        }

        return makeLease(.interactive, for: coordinator)
    }

    /// Reuses the live coordinator or boots one headless, then waits for its durability part.
    /// - Returns: `nil` when the app is not ready for dashboard services or the durability part failed to start.
    func acquireDurability() async -> DashboardServicesLease<Coordinator>? {
        guard let coordinator = await existingOrHeadlessCoordinator() else { return nil }

        let lease = makeLease(.durability, for: coordinator)

        guard await coordinator.startDurability() else {
            lease.release()
            return nil
        }

        return lease
    }

    /// Stops and drops everything; leases issued before are ignored when released.
    func reset() {
        generation &+= 1
        headlessBoot?.cancel()
        headlessBoot = nil
        coordinator?.stopAll()
        coordinator = nil
        leaseCounts = [:]
    }
}

private extension DashboardServicesManager {
    func existingOrNewCoordinator() -> Coordinator? {
        if let coordinator {
            return coordinator
        }

        coordinator = coordinatorFactory.makeCoordinator()
        return coordinator
    }

    func existingOrHeadlessCoordinator() async -> Coordinator? {
        if let coordinator {
            return coordinator
        }

        if let headlessBoot {
            return await headlessBoot.value
        }

        let boot = Task { await bootHeadless(generation: generation) }
        headlessBoot = boot
        let result = await boot.value
        headlessBoot = nil
        return result
    }

    func bootHeadless(generation bootGeneration: UInt64) async -> Coordinator? {
        bootstrapper.start()

        let readiness = await bootstrapper.waitReady(deadline: headlessBootDeadline)

        guard readiness == .dashboard else {
            logger.info("Headless boot skipped: \(readiness)")
            return nil
        }

        guard bootGeneration == generation, !Task.isCancelled else { return nil }

        // The dashboard may have created it while the boot waited.
        return existingOrNewCoordinator()
    }

    func leaseCount(for demand: DashboardServicesDemand) -> Int {
        leaseCounts[demand, default: 0]
    }

    func makeLease(
        _ demand: DashboardServicesDemand,
        for coordinator: Coordinator
    ) -> DashboardServicesLease<Coordinator> {
        leaseCounts[demand, default: 0] += 1

        return DashboardServicesLease(coordinator: coordinator, demand: demand, generation: generation) { [weak self] in
            self?.didRelease($0)
        }
    }

    func didRelease(_ lease: DashboardServicesLease<Coordinator>) {
        guard
            lease.generation == generation,
            let coordinator,
            coordinator === lease.coordinator
        else {
            return
        }

        leaseCounts[lease.demand] = max(leaseCount(for: lease.demand) - 1, 0)

        let hasInteractive = leaseCount(for: .interactive) > 0
        let hasDurability = leaseCount(for: .durability) > 0

        switch (lease.demand, hasInteractive, hasDurability) {
        case (_, false, false):
            coordinator.stopAll()
            self.coordinator = nil
        case (.interactive, false, true):
            coordinator.stopInteractive()
        default:
            break
        }
    }
}
