import Foundation

/// App-wide instances behind the dashboard: one flow state and one services manager per process, shared by the
/// dashboard and background renewal.
enum DashboardServices {
    static let flowStateProvider: SPAFlowStateProviding = SPAFlowStateProvider()

    @MainActor static let manager = DashboardServicesManager<ServiceCoordinator>(
        bootstrapper: LaunchBootstrapper.shared,
        coordinatorFactory: ServiceCoordinatorFactory(flowStateProvider: flowStateProvider),
        connectionRetention: ChainRegistryConnectionRetention(),
        headlessBootDeadline: .seconds(20),
        logger: Logger.shared
    )
}

struct ServiceCoordinatorFactory: DashboardServicesCoordinatorMaking {
    let flowStateProvider: SPAFlowStateProviding

    @MainActor
    func makeCoordinator() -> ServiceCoordinator? {
        ServiceCoordinator.createDefault(spaFlowState: flowStateProvider.flowState())
    }
}
