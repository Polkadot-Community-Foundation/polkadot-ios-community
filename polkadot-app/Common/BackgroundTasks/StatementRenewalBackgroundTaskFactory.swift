import BackgroundExecution
import FoundationExt
import UIKit

/// Builds the background task that keeps statements and allowances renewed while the app is closed.
enum StatementRenewalBackgroundTaskFactory {
    private static let identifierSuffix = ".statement-renewal"
    private static let logTag = "BGRenewal"

    private static let policy = BackgroundTaskRequestPolicy(
        earliestBeginDelay: 60 * 60,
        constraints: BackgroundTaskConstraints(requiresNetworkConnectivity: true, requiresExternalPower: false)
    )

    static func make(baseLogger: LoggerProtocol = Logger.shared) -> ScheduledBackgroundTask? {
        let logger = TaggedLogger(tag: logTag, logger: baseLogger)

        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            logger.error("no bundle identifier, task not created")
            return nil
        }

        return ScheduledBackgroundTask(
            identifier: bundleIdentifier + identifierSuffix,
            policy: policy,
            dependencies: ScheduledBackgroundTaskDependencies(
                scheduler: BGTaskSchedulerAdapter(),
                dateProvider: NowDateProvider(),
                logger: logger
            ),
            work: { await describeLaunch() }
        )
    }
}

private extension StatementRenewalBackgroundTaskFactory {
    // TODO: Replace with the renewal run (T5); until then the run only records how iOS launched the app.
    @MainActor
    static func describeLaunch() -> BackgroundTaskWorkOutcome {
        let application = UIApplication.shared
        let sceneStates = application.connectedScenes.map { "\($0.activationState.rawValue)" }

        let fields = "connectedScenes=\(sceneStates.count) sceneStates=[\(sceneStates.joined(separator: ","))]"
            + " applicationState=\(application.applicationState.rawValue)"

        return .completed(logFields: fields)
    }
}
