import Foundation

enum MarketDataCatalog {
    static let symbols = ["005930", "000660", "035420", "005380"]

    static let quotes: [StockQuote] = [
        StockQuote(symbol: "005930", price: Decimal(73400), changePercent: Decimal(string: "1.24") ?? 1.24),
        StockQuote(symbol: "000660", price: Decimal(181200), changePercent: Decimal(string: "-0.82") ?? -0.82),
        StockQuote(symbol: "035420", price: Decimal(214500), changePercent: Decimal(string: "0.46") ?? 0.46),
        StockQuote(symbol: "005380", price: Decimal(267000), changePercent: Decimal(string: "2.08") ?? 2.08)
    ]

    static func quote(for symbol: String?) -> StockQuote {
        guard let symbol,
              let quote = quotes.first(where: { $0.symbol == symbol }) else {
            return quotes[0]
        }
        return quote
    }

    static func chartSeries(for symbol: String?) -> StockChartSeries {
        let quote = quote(for: symbol)
        let calendar = Calendar(identifier: .gregorian)
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 19, hour: 9, minute: 30)) ?? Date()
        let base = quote.price
        let points = stride(from: 0, through: 12, by: 1).compactMap { index -> StockTimeSeriesPoint? in
            guard let date = calendar.date(byAdding: .minute, value: index * 30, to: startDate) else {
                return nil
            }
            let wave = Decimal(sin(Double(index) * 0.72) * 1400)
            let lift = Decimal(index * 360)
            return StockTimeSeriesPoint(date: date, close: base - Decimal(2600) + wave + lift)
        }
        return StockChartSeries(symbol: quote.symbol, points: points)
    }
}
