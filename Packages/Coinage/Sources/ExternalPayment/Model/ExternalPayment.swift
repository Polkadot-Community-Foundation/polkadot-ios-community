import BigInt
import Foundation
import Operation_iOS
import SubstrateSdk

public struct ExternalPayment: Equatable {
    public enum Stage: Int {
        case plan = 0
        case onboardCoins = 1
        case offboardVouchers = 2
        case completed = 3
        case failed = 4
        case partiallyCompleted = 5

        public var isTerminal: Bool {
            switch self {
            case .completed,
                 .failed,
                 .partiallyCompleted:
                true
            case .plan,
                 .onboardCoins,
                 .offboardVouchers:
                false
            }
        }
    }

    /// Storage identifier, always ``identifier(productId:paymentId:)``.
    public let id: String
    /// The product that owns `paymentId`; the in-app pay flow uses ``ExternalPayment/nativeProductId``.
    public let productId: String
    public let paymentId: String
    public let amountInPlanks: Balance
    public let destination: AccountId
    /// Value delivered to `destination` by finalized unloads; set on completion and partial completion.
    public var settledInPlanks: Balance
    public var stage: Stage
    /// Vouchers the current stage carries: the exact vouchers while onboarding, the vouchers to unload
    /// while offboarding. Persisted so a relaunch resumes without re-planning.
    public var plannedVoucherIndices: [DerivationIndex]
    public var failureReason: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        productId: String,
        paymentId: String,
        amountInPlanks: Balance,
        destination: AccountId,
        settledInPlanks: Balance = 0,
        stage: Stage = .plan,
        plannedVoucherIndices: [DerivationIndex] = [],
        failureReason: String? = nil,
        createdAt: Date = .init(),
        updatedAt: Date = .init()
    ) {
        id = Self.identifier(productId: productId, paymentId: paymentId)
        self.productId = productId
        self.paymentId = paymentId
        self.amountInPlanks = amountInPlanks
        self.destination = destination
        self.settledInPlanks = settledInPlanks
        self.stage = stage
        self.plannedVoucherIndices = plannedVoucherIndices
        self.failureReason = failureReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public extension ExternalPayment {
    /// The product id the wallet's own pay flow registers under.
    static let nativeProductId = "native-payment"

    /// Identity is `(productId, paymentId)`: the same product-supplied id under two products is two
    /// payments. The prefix keeps the id unique among durability group ids as well.
    static func identifier(productId: String, paymentId: String) -> String {
        "external-payment:\(productId):\(paymentId)"
    }
}

extension ExternalPayment: Operation_iOS.Identifiable {
    public var identifier: String { id }
}
