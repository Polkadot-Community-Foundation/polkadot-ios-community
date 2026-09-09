/// The single value the status ring renders, derived from connection state alone.
/// `resolve` is total and clock-free: everything time-dependent — the dwell today, liveness
/// next — stays with the provider that already owns state.
public enum ChainStatusIndication: Hashable {
    case normal
    case dead

    public static func resolve(state: ChainConnectionState) -> ChainStatusIndication {
        switch state {
        case .connected:
            .normal
        case .connecting,
             .offline:
            .dead
        }
    }
}
