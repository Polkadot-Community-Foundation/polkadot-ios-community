import Foundation
import FoundationExt

struct FixedDateProvider: DateProviding {
    let date: Date

    func read() async -> Date {
        date
    }
}
