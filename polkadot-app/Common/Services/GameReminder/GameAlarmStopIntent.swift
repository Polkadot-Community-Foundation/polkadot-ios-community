import Foundation
import AlarmKit
import AppIntents

@available(iOS 26.1, *)
struct GameAlarmPlayIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Join"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Alarm ID") // hardcoded-string:ignore
    var alarmID: String?

    @Parameter(title: "Product ID") // hardcoded-string:ignore
    var productId: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        if let productId {
            ProductOpener().open(productId: productId)
        }

        if let alarmIDString = alarmID,
           let alarmUUID = UUID(uuidString: alarmIDString) {
            try? AlarmManager.shared.stop(id: alarmUUID)
        }

        return .result()
    }
}
