import Foundation
import FoundationExt
import os
import SDKLogger

/// How every request for a task is built; the delay becomes an absolute date at each submit.
public struct BackgroundTaskRequestPolicy: Sendable {
    public let earliestBeginDelay: TimeInterval
    public let constraints: BackgroundTaskConstraints

    public init(earliestBeginDelay: TimeInterval, constraints: BackgroundTaskConstraints) {
        self.earliestBeginDelay = earliestBeginDelay
        self.constraints = constraints
    }
}

public struct ScheduledBackgroundTaskDependencies {
    let scheduler: any BackgroundTaskScheduling
    let dateProvider: any DateProviding
    let logger: SDKLoggerProtocol

    public init(
        scheduler: any BackgroundTaskScheduling,
        dateProvider: any DateProviding,
        logger: SDKLoggerProtocol
    ) {
        self.scheduler = scheduler
        self.dateProvider = dateProvider
        self.logger = logger
    }
}

/// What a run achieved; `logFields` are appended verbatim to the `finished` log line.
public enum BackgroundTaskWorkOutcome: Sendable, Equatable {
    case completed(logFields: String)
    case skipped(reason: String)
}

public typealias BackgroundTaskWork = @Sendable () async throws -> BackgroundTaskWorkOutcome

/// Owns the OS contract for one background task: registered once, one request kept queued, the work cancelled on
/// expiry and the task completed exactly once. Every step is logged as one event line; callers tag the logger.
public final class ScheduledBackgroundTask {
    private let identifier: String
    private let policy: BackgroundTaskRequestPolicy
    private let dependencies: ScheduledBackgroundTaskDependencies
    private let work: BackgroundTaskWork
    private let isRegistered = OSAllocatedUnfairLock(initialState: false)

    public init(
        identifier: String,
        policy: BackgroundTaskRequestPolicy,
        dependencies: ScheduledBackgroundTaskDependencies,
        work: @escaping BackgroundTaskWork
    ) {
        self.identifier = identifier
        self.policy = policy
        self.dependencies = dependencies
        self.work = work
    }
}

extension ScheduledBackgroundTask: @unchecked Sendable {
    /// Call synchronously before the app finishes launching. Repeated calls are ignored, because the OS kills
    /// the app on a second registration of the same identifier.
    public func register() {
        let wasRegistered = isRegistered.withLock { registered in
            defer { registered = true }
            return registered
        }

        guard !wasRegistered else { return }

        let accepted = dependencies.scheduler.register(identifier: identifier) { [weak self] task in
            _ = self?.handle(task)
        }

        if accepted {
            dependencies.logger.debug("Did register processing task with \(identifier)")
        } else {
            dependencies.logger.error("registerRejected id=\(identifier) not in permitted identifiers")
        }
    }

    /// Whether the OS currently holds a request for this task.
    public func isRequestPending() async -> Bool {
        await dependencies.scheduler.pendingRequestIdentifiers().contains(identifier)
    }

    /// Queues the next launch, replacing any pending request for this identifier.
    public func schedule() async {
        let now = await dependencies.dateProvider.read()
        let earliestBegin = now.addingTimeInterval(policy.earliestBeginDelay)
        let request = BackgroundTaskRequest(
            identifier: identifier,
            earliestBeginDate: earliestBegin,
            constraints: policy.constraints
        )

        do {
            try dependencies.scheduler.submit(request)
            dependencies.logger.info("submitted id=\(identifier) earliestBegin=\(earliestBegin)")
        } catch {
            dependencies.logger.warning("submitFailed id=\(identifier) error=\(error)")
        }
    }
}

extension ScheduledBackgroundTask {
    /// Runs one launch of the task. Returns the run so tests can await it; the OS path ignores it.
    func handle(_ task: any BackgroundTaskHandle) -> Task<Void, Never> {
        let completion = TaskCompletion(task: task, identifier: identifier, logger: dependencies.logger)

        dependencies.logger.info("started id=\(identifier)")

        let run = Task { [self] in
            // Queued first, so a crash or expiry inside the work never leaves the chain without a next launch.
            await schedule()
            let result = await runWork()
            completion.finish(with: result)
        }

        task.expirationHandler = {
            run.cancel()
            completion.finish(with: .expired)
        }

        return run
    }
}

private extension ScheduledBackgroundTask {
    func runWork() async -> TaskCompletion.Result {
        do {
            let outcome = try await work()
            return Task.isCancelled ? .expired : .finished(outcome)
        } catch {
            return Task.isCancelled ? .expired : .failed(String(describing: type(of: error)))
        }
    }
}

/// Completes a task at most once; expiry and the work finishing race to get here.
private final class TaskCompletion: @unchecked Sendable {
    enum Result {
        case finished(BackgroundTaskWorkOutcome)
        case failed(String)
        case expired
    }

    private let task: any BackgroundTaskHandle
    private let identifier: String
    private let logger: SDKLoggerProtocol
    private let isCompleted = OSAllocatedUnfairLock(initialState: false)

    init(task: any BackgroundTaskHandle, identifier: String, logger: SDKLoggerProtocol) {
        self.task = task
        self.identifier = identifier
        self.logger = logger
    }

    func finish(with result: Result) {
        let wasCompleted = isCompleted.withLock { completed in
            defer { completed = true }
            return completed
        }

        guard !wasCompleted else { return }

        logger.info("finished id=\(identifier) \(result.logFields)")
        task.setTaskCompleted(success: result.isSuccess)
    }
}

private extension TaskCompletion.Result {
    var isSuccess: Bool {
        if case .finished = self { true } else { false }
    }

    var logFields: String {
        switch self {
        case let .finished(.completed(fields)): "outcome=completed \(fields)"
        case let .finished(.skipped(reason)): "outcome=skipped reason=\(reason)"
        case let .failed(errorType): "outcome=failed error=\(errorType)"
        case .expired: "outcome=expired"
        }
    }
}
