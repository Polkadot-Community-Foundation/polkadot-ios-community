import Foundation

public protocol AllowanceRenewalFiltering {
    /// The stale records to renew this period; the others stay as they are, neither renewed nor dropped.
    func renewable(_ records: [AllowanceRecord]) async throws -> [AllowanceRecord]
}
