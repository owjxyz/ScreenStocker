import Foundation

struct StockQuote: Equatable {
    let symbol: String
    let price: Decimal
    let changePercent: Decimal

    var priceText: String {
        "$\(price)"
    }

    var changePercentText: String {
        "\(changePercent)%"
    }
}

