import Foundation
import AsyncExtensions
@testable import polkadot_app

final class MockStatementDeliveryTracker: StatementDeliveryTracking {
    private let subject = AsyncCurrentValueSubject<StatementDeliveryState>(.noSubscriptions)

    func stateStream() -> AnyAsyncSequence<StatementDeliveryState> {
        subject.eraseToAnyAsyncSequence()
    }

    func report(_ state: StatementDeliveryState) {
        subject.send(state)
    }
}
