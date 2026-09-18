import Foundation

struct PaymentAssetConfig: Equatable {
    let symbol: String?
    let squareIconURL: URL?
    let wideIconURL: URL?

    init(symbol: String?, squareIconURL: URL?, wideIconURL: URL?) {
        self.symbol = symbol
        self.squareIconURL = squareIconURL
        self.wideIconURL = wideIconURL
    }

    init?(json: [String: String]) {
        let symbol = json[Key.symbol].flatMap(Self.nonEmpty)
        let squareIconURL = json[Key.squareIcon].flatMap(Self.webURL)
        let wideIconURL = json[Key.wideIcon].flatMap(Self.webURL)

        guard symbol != nil || squareIconURL != nil || wideIconURL != nil else {
            return nil
        }

        self.init(symbol: symbol, squareIconURL: squareIconURL, wideIconURL: wideIconURL)
    }
}

extension PaymentAssetConfig {
    enum Key {
        static let symbol = "symbol"
        static let squareIcon = "iconSquareUrl"
        static let wideIcon = "iconWideUrl"
    }
}

private extension PaymentAssetConfig {
    static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func webURL(_ value: String) -> URL? {
        guard
            let trimmed = nonEmpty(value),
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            ["https", "http"].contains(scheme),
            url.host() != nil
        else {
            return nil
        }

        return url
    }
}

enum PaymentAssetSymbol {
    private static let lock = NSLock()
    private static var value = AppConfig.Brand.cashSymbol

    static var current: String {
        lock.withLock { value }
    }

    static func update(_ symbol: String) {
        lock.withLock { value = symbol }
    }
}
