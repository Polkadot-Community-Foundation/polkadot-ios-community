import BackgroundExecution

/// What Debug Settings needs to check and drive background renewal by hand.
struct DebugRenewalTools {
    let task: ScheduledBackgroundTask?
    let work: StatementRenewalBackgroundWork
}
