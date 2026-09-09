import Testing
@testable import PolkadotUI

struct ChainStatusIndicationTests {
    @Test(
        "Each connection state resolves to its indication",
        arguments: [
            (ChainConnectionState.connected, ChainStatusIndication.normal),
            (ChainConnectionState.connecting, ChainStatusIndication.dead),
            (ChainConnectionState.offline, ChainStatusIndication.dead)
        ]
    )
    func resolvesStateToIndication(state: ChainConnectionState, expectedIndication: ChainStatusIndication) {
        #expect(ChainStatusIndication.resolve(state: state) == expectedIndication)
    }
}
