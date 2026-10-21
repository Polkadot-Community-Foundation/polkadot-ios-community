import Foundation
import BackgroundExecution

/// The executor lives here so the OS background task can drive the renewal service under its own expiration.
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
