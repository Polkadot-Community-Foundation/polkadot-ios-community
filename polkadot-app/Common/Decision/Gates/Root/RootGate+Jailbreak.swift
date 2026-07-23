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
            // The public Dev/W3S build (‑DDEV) is a testnet developer build distributed via
            // TestFlight; jailbroken devices are a legitimate tester setup there, so the block is
            // compiled out for DEV as well as DEBUG. Nightly and Release keep the gate active.
            #if !DEBUG && !DEV
                if detector.isJailbroken() {
                    logger.error("Jailbreak detected - blocking app execution")
                    return .jailbroken
                }
            #endif

            return nil
        }
    }
}
