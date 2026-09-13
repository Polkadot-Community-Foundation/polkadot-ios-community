import Foundation
import StateMachine
import SubstrateSdk

/// Recycles the selected coins under the payment's own durability group and awaits that group's
/// outcome through the recycler. On `allRecycled` (best-block inclusion is enough) the exact vouchers
/// plus the recycled ones are checked against the amount and handed to offboarding; `incomplete`, a
/// shortfall and any thrown error fail the payment — there are no retries.
///
/// The exact vouchers are persisted with the stage, so a relaunch (`coins` empty) re-joins the group
/// and continues with the same selection. A relaunch that finds no group registered goes back to
/// planning: the crash happened before anything was submitted.
struct OnboardCoinsPaymentState: StateMachineState {
    typealias StateFactory = ExternalPaymentStateFactory
    typealias PersistentValue = ExternalPayment

    let payment: ExternalPayment
    let coins: [Coin]
    let exactVoucherIndices: [DerivationIndex]
    let isTerminal = false

    static func recyclingGroupId(for payment: ExternalPayment) -> CoinageTxGroupId {
        "\(payment.id):recycle"
    }

    func transit(
        with factory: ExternalPaymentStateFactory
    ) async -> AnyStateMachineState<ExternalPaymentStateFactory, ExternalPayment> {
        let groupId = Self.recyclingGroupId(for: payment)

        do {
            try await factory.recycler.recycleCoins(coins, groupId: groupId)

            guard try await !factory.durability.getOperationGroupStatuses(groupId).isEmpty else {
                return coins.isEmpty
                    ? factory.makePlanState(payment: payment)
                    : factory.makeFailedState(payment: payment, reason: "recycling submission failed")
            }

            for try await status in factory.recycler.observeRecycling(groupId: groupId) {
                switch status {
                case .pending:
                    continue
                case .incomplete:
                    return factory.makeFailedState(payment: payment, reason: "recycling incomplete")
                case let .allRecycled(recycled, finalized):
                    factory.logger?.debug(
                        "Payment \(payment.id): \(recycled.count) vouchers recycled, finalized \(finalized)"
                    )
                    return try await offboard(recycled: recycled.map(\.voucher), factory: factory)
                }
            }

            return factory.makeFailedState(payment: payment, reason: "recycling stream ended")
        } catch {
            return factory.makeFailedState(payment: payment, reason: error.localizedDescription)
        }
    }

    func memo() async -> ExternalPayment {
        var currentPayment = payment
        currentPayment.stage = .onboardCoins
        currentPayment.plannedVoucherIndices = exactVoucherIndices
        currentPayment.updatedAt = Date()
        return currentPayment
    }
}

private extension OnboardCoinsPaymentState {
    func offboard(
        recycled: [Voucher],
        factory: ExternalPaymentStateFactory
    ) async throws -> AnyStateMachineState<ExternalPaymentStateFactory, ExternalPayment> {
        let exact = try await factory.voucherService
            .fetchTracked(derivationIndices: Set(exactVoucherIndices))
            .map(\.voucher)
        let vouchers = exact + recycled
        let covered = vouchers.reduce(Balance(0)) { $0 + factory.context.valueInPlanks(for: $1.exponent) }

        guard covered >= payment.amountInPlanks else {
            return factory.makeFailedState(payment: payment, reason: "insufficient balance after recycling")
        }

        return factory.makeOffboardVouchersState(payment: payment, vouchers: vouchers)
    }
}
