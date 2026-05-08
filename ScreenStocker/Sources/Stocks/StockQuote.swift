import Foundation

struct StockQuote: Equatable {
    let symbol: String
    let price: Decimal
    let changePercent: Decimal

    var priceText: String {
        Self.currencyText(for: price)
    }

    var changePercentText: String {
        "\(Self.percentFormatter.string(for: changePercent) ?? "\(changePercent)")%"
    }

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func currencyText(for value: Decimal) -> String {
        "$\(decimalFormatter.string(for: value) ?? "\(value)")"
    }
}

struct StockSymbolSearchResult: Equatable {
    let symbol: String
    let name: String
    let exchange: String?
    let country: String?
    let currency: String?
    let type: String?

    var displayTitle: String {
        let market = [exchange, country].compactMap { $0 }.joined(separator: ", ")
        guard !market.isEmpty else { return "\(symbol) - \(name)" }
        return "\(symbol) - \(name) (\(market))"
    }
}
