import Foundation

protocol StockQuoteProvider {
    func fetchQuotes(completion: @escaping ([StockQuote]) -> Void)
}

final class DemoStockQuoteProvider: StockQuoteProvider {
    private let symbols: [String]

    init(symbols: [String]) {
        self.symbols = symbols
    }

    func fetchQuotes(completion: @escaping ([StockQuote]) -> Void) {
        let quotes = symbols.enumerated().map { index, symbol in
            StockQuote(
                symbol: symbol,
                price: Decimal(140 + index * 17),
                changePercent: Decimal(index.isMultiple(of: 2) ? 1.24 : -0.82)
            )
        }
        completion(quotes)
    }
}

