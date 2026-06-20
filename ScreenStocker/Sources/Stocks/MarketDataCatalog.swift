import Foundation

enum MarketDataCatalog {
    static let symbols = ["005930", "000660", "035420", "005380"]

    static func quote(for symbol: String?) -> StockQuote {
        StockQuote.placeholder(symbol: symbol ?? symbols.first)
    }

    static func chartSeries(for symbol: String?) -> StockChartSeries {
        StockChartSeries(symbol: symbol ?? symbols.first ?? "-", points: [])
    }
}
