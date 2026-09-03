import Foundation
import JailbreakDetection

extension RootGate {
    struct Jailbreak: DecisionGate {
        private let detector: JailbreakDetector
        private let logger: LoggerProtocol

        init(detector: JailbreakDetector, logger: LoggerProtocol) {
            self.detector = detector
            self.logger = logger
        }

        func evaluate() -> RootDestination? {
            // `JailbreakDetector.isJailbroken()` reports `true` for ANY
            // simulator (`isJailbroken || device.isSimulator`), which would
            // hard-block the triangle-e2e iOS shard (a Nightly simulator
            // build). Skip the gate for the E2E_TEST artifact in addition to
            // DEBUG. Every other build — including a plain Nightly simulator
            // build used during dev — runs the full jailbreak check unchanged.
            //
            // The public Dev/W3S build (‑DDEV) is a testnet developer build distributed via
            // TestFlight; jailbroken devices are a legitimate tester setup there, so the block is
            // compiled out for DEV as well. Nightly and Release keep the gate active.
            #if !DEBUG && !E2E_TEST && !DEV
                if detector.isJailbroken() {
                    logger.error("Jailbreak detected - blocking app execution")
                    return .jailbroken
                }
            #endif

            return nil
        }
    }
}
