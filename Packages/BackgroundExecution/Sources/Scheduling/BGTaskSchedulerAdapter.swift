import BackgroundTasks

/// The only type that talks to `BGTaskScheduler`; every request is a `BGProcessingTaskRequest`.
public struct BGTaskSchedulerAdapter: BackgroundTaskScheduling {
    public init() {}

    public func register(
        identifier: String,
        launchHandler: @escaping @Sendable (any BackgroundTaskHandle) -> Void
    ) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            launchHandler(BGTaskHandle(task: task))
        }
    }

    public func submit(_ request: BackgroundTaskRequest) throws {
        let processingRequest = BGProcessingTaskRequest(identifier: request.identifier)
        processingRequest.earliestBeginDate = request.earliestBeginDate
        processingRequest.requiresNetworkConnectivity = request.constraints.requiresNetworkConnectivity
        processingRequest.requiresExternalPower = request.constraints.requiresExternalPower

        try BGTaskScheduler.shared.submit(processingRequest)
    }

    public func pendingRequestIdentifiers() async -> [String] {
        await BGTaskScheduler.shared.pendingTaskRequests().map(\.identifier)
    }
}

/// `BGTask` is not `Sendable`; this wrapper is the single place that touches it.
final class BGTaskHandle: BackgroundTaskHandle, @unchecked Sendable {
    private let task: BGTask

    init(task: BGTask) {
        self.task = task
    }

    var expirationHandler: (@Sendable () -> Void)? {
        didSet { task.expirationHandler = expirationHandler }
    }

    func setTaskCompleted(success: Bool) {
        task.setTaskCompleted(success: success)
    }
}
