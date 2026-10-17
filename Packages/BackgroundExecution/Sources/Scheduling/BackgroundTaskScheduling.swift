import Foundation

/// Conditions the OS waits for before launching a task.
public struct BackgroundTaskConstraints: Sendable, Equatable {
    public let requiresNetworkConnectivity: Bool
    public let requiresExternalPower: Bool

    public init(requiresNetworkConnectivity: Bool, requiresExternalPower: Bool) {
        self.requiresNetworkConnectivity = requiresNetworkConnectivity
        self.requiresExternalPower = requiresExternalPower
    }
}

/// A request for the OS to launch the app in the background to run the task with `identifier`.
public struct BackgroundTaskRequest: Sendable, Equatable {
    public let identifier: String
    public let earliestBeginDate: Date?
    public let constraints: BackgroundTaskConstraints

    public init(identifier: String, earliestBeginDate: Date?, constraints: BackgroundTaskConstraints) {
        self.identifier = identifier
        self.earliestBeginDate = earliestBeginDate
        self.constraints = constraints
    }
}

/// The OS background task scheduler, behind a protocol so the task contract is testable off-device.
public protocol BackgroundTaskScheduling: Sendable {
    /// Registers the launch handler for `identifier`. Must complete before the app finishes launching.
    /// - Returns: `false` when the identifier is missing from `BGTaskSchedulerPermittedIdentifiers`.
    func register(
        identifier: String,
        launchHandler: @escaping @Sendable (any BackgroundTaskHandle) -> Void
    ) -> Bool

    /// Queues `request`, replacing a pending request with the same identifier.
    func submit(_ request: BackgroundTaskRequest) throws

    func pendingRequestIdentifiers() async -> [String]
}

/// A task the OS launched the app for.
public protocol BackgroundTaskHandle: AnyObject, Sendable {
    /// Called by the OS shortly before the task's background time expires.
    var expirationHandler: (@Sendable () -> Void)? { get set }

    func setTaskCompleted(success: Bool)
}
