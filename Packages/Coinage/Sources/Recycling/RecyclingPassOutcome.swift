import Foundation

/// What one awaited recycling pass did. Submission means handed to the durable engine, not included on chain.
public enum RecyclingPassOutcome: Sendable, Equatable {
    /// Coinage setup has not finished, so there is no evaluator to run.
    case notReady
    /// The wallet snapshot or the evaluation could not be read.
    case failed
    case completed(evaluatedCoins: Int, gated: Int, submitted: Int)
}
