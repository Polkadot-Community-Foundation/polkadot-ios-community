import Foundation
import BackgroundExecution

/// Renews hourly while the dashboard runs. Each pass holds a background-task assertion; the renewal service itself
/// stays executor-free so the OS background task can drive it under its own expiration.
struct ChatRequestRenewalLoop {
    private static let interval: Duration = .seconds(60 * 60)

    let durabilityRenewal: StatementDurabilityRenewing
    let backgroundExecutor: BackgroundExecuting

    func run() async {
        while !Task.isCancelled {
            _ = try? await backgroundExecutor.execute {
                await durabilityRenewal.renewAll()
            }
            try? await Task.sleep(for: Self.interval)
        }
    }
}
