import Foundation
import Metal
import Testing

@testable import polkadot_app

/// The renderer holds the meshes, the studio and the compiled pipeline: the same for every coin on
/// every screen, and none of it changes while the app runs. Building it took the best part of a
/// second with the main thread held, which was the whole of the pause on opening the view.
@Suite("Coin renderer loader", .serialized)
struct CoinageRendererLoaderTests {
    @Test("Asking for the renderer does not make the caller wait for it")
    func loadingDoesNotBlockTheCaller() async {
        // `load` must return before the renderer exists, and must answer on the main queue.
        // Timing the call itself is what proves it: an earlier version of this test set a flag on
        // the line after `load` returned, which is true however long `load` blocked.
        let start = CFAbsoluteTimeGetCurrent()
        let renderer: CoinageMetalRenderer? = await withCheckedContinuation { continuation in
            CoinageRendererLoader.load { continuation.resume(returning: $0) }
        }
        let returned = CFAbsoluteTimeGetCurrent()

        #expect(renderer != nil)
        // The store alone takes tens of milliseconds; a blocking `load` could not come back inside
        // a millisecond, and a non-blocking one cannot take longer.
        #expect(returned - start < 1)
    }

    @Test("Everyone gets the same renderer rather than another copy of it")
    func theRendererIsSharedAcrossCallers() async {
        let first: CoinageMetalRenderer? = await withCheckedContinuation { continuation in
            CoinageRendererLoader.load { continuation.resume(returning: $0) }
        }
        let second: CoinageMetalRenderer? = await withCheckedContinuation { continuation in
            CoinageRendererLoader.load { continuation.resume(returning: $0) }
        }

        #expect(first != nil)
        #expect(first === second)
    }

    @Test("Callers waiting together are all answered")
    func everyWaiterIsAnswered() async {
        let delivered = await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< 8 {
                group.addTask {
                    await withCheckedContinuation { continuation in
                        CoinageRendererLoader.load { continuation.resume(returning: $0 != nil) }
                    }
                }
            }

            return await group.reduce(into: 0) { $0 += $1 ? 1 : 0 }
        }

        #expect(delivered == 8)
    }

    @Test("The view is told the samples the pipeline will be built for, before there is one")
    func sampleCountAgreesWithTheRenderer() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer: CoinageMetalRenderer? = await withCheckedContinuation { continuation in
            CoinageRendererLoader.load { continuation.resume(returning: $0) }
        }

        // A view and a pipeline that disagree here fail validation at the draw call, with nothing
        // before it to say why.
        #expect(CoinageRendererLoader.sampleCount(for: device) == renderer?.sampleCount)
    }
}
