import Foundation

/// Which Core Data stack a benchmark runs against. Every timing test is parameterized over
/// `supported`, so old and new implementations are measured in the same process and run.
enum StackVariant: String, CaseIterable, Sendable {
    /// Operation-iOS 2.7.0: one private-queue context serves reads, writes and observation.
    case serial

    /// Variants the currently linked Operation-iOS can build. Phase 2 appends the concurrent cases.
    static let supported: [StackVariant] = [.serial]
}
