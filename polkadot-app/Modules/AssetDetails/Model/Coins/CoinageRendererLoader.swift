import Metal

/// Builds the one renderer, once, away from the main thread.
///
/// Everything it owns — the meshes, the studio, the relief atlas, the compiled pipeline — is the
/// same for every coin on every screen, and none of it changes while the app runs. It used to be
/// built in the view's coordinator, so it happened again on every appearance and, worse, with the
/// main thread held: about three hundred milliseconds of assets and, the first time, another four
/// hundred or so for Metal to compile the pipeline. That is the whole of the pause between tapping
/// the card and anything happening.
///
/// Callers get the renderer when it is ready and draw nothing until then, which is a frame or two
/// of an empty strip rather than a frozen tap.
enum CoinageRendererLoader {
    /// The samples the pipeline will be built for, before there is a pipeline to ask.
    ///
    /// The view has to be configured the moment it is made, and a view and a pipeline that
    /// disagree on samples fail validation at the draw call with nothing to say why. Asked of the
    /// device rather than remembered, so the two answers cannot drift apart.
    static func sampleCount(for device: MTLDevice?) -> Int {
        device?.supportsTextureSampleCount(4) == true ? 4 : 1
    }

    /// Hands over the renderer, building it first if nobody has yet.
    ///
    /// Always answers on the main queue and never inline, so a caller has the same shape of life
    /// whether it is the first to ask or the hundredth.
    static func load(_ deliver: @escaping (CoinageMetalRenderer?) -> Void) {
        let work: (() -> Void)? = state.withLock { current in
            switch current {
            case let .ready(renderer):
                return { DispatchQueue.main.async { deliver(renderer) } }
            case .loading:
                waiting.withLock { $0.append(deliver) }
                return nil
            case .idle:
                current = .loading
                waiting.withLock { $0.append(deliver) }
                return build
            }
        }

        work?()
    }

    private enum State {
        case idle
        case loading
        case ready(CoinageMetalRenderer?)
    }

    private static let state = Guarded(State.idle)
    private static let waiting = Guarded([(CoinageMetalRenderer?) -> Void]())

    private static func build() {
        DispatchQueue.global(qos: .userInitiated).async {
            let renderer = try? CoinageMetalRenderer()

            state.withLock { $0 = .ready(renderer) }

            let deliveries = waiting.withLock { waiting -> [(CoinageMetalRenderer?) -> Void] in
                defer { waiting = [] }

                return waiting
            }

            DispatchQueue.main.async {
                for deliver in deliveries {
                    deliver(renderer)
                }
            }
        }
    }
}

/// A value only one thread touches at a time. `NSLock` rather than a queue: every critical section
/// here is a field read or a field write.
private final class Guarded<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }

        return body(&value)
    }
}
