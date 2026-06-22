import Foundation

struct StockQuote: Equatable {
    let symbol: String
    var displayName: String?
    var exchangeLabel: String?
    let price: Decimal?
    let changePercent: Decimal?
    var currency: String = "KRW"
    var timestamp: Date?

    var titleText: String {
        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName?.isEmpty == false ? trimmedName! : symbol
    }

    var priceText: String {
        Self.currencyText(for: price, currency: currency)
    }

    var changePercentText: String {
        guard let changePercent else { return "-" }
        return "\(Self.percentFormatter.string(for: changePercent) ?? "\(changePercent)")%"
    }

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let krwFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"
        return formatter
    }()

    static func currencyText(for value: Decimal?, currency: String = "KRW") -> String {
        guard let value else { return "-" }
        let normalizedCurrency = currency.uppercased()
        let symbol = normalizedCurrency == "USD" ? "$" : "₩"
        let formatter = normalizedCurrency == "KRW" ? krwFormatter : decimalFormatter
        return "\(symbol)\(formatter.string(for: value) ?? "\(value)")"
    }

    static func placeholder(symbol: String?) -> StockQuote {
        StockQuote(symbol: symbol ?? "-", displayName: nil, exchangeLabel: nil, price: nil, changePercent: nil)
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
