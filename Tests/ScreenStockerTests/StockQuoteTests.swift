import XCTest

final class StockQuoteTests: XCTestCase {
    func testMarketDataCatalogDoesNotReturnDummyQuoteValues() {
        let quote = MarketDataCatalog.quote(for: "000660")

        XCTAssertEqual(quote.symbol, "000660")
        XCTAssertNil(quote.price)
        XCTAssertNil(quote.changePercent)
        XCTAssertEqual(quote.priceText, "-")
        XCTAssertEqual(quote.changePercentText, "-")
    }

    func testMarketDataCatalogDoesNotGenerateDummyChartSeries() {
        let series = MarketDataCatalog.chartSeries(for: "035420")

        XCTAssertEqual(series.symbol, "035420")
        XCTAssertTrue(series.points.isEmpty)
        XCTAssertNil(series.highClose)
        XCTAssertNil(series.lowClose)
    }

    func testKRWPriceTextOmitsFractionDigits() {
        let quote = StockQuote(symbol: "005930", price: Decimal(75300), changePercent: nil, currency: "KRW")

        XCTAssertEqual(quote.priceText, "₩75,300")
    }

    func testUSDPriceTextKeepsFractionDigits() {
        let quote = StockQuote(symbol: "AAPL", price: Decimal(string: "123.45"), changePercent: nil, currency: "USD")

        XCTAssertEqual(quote.priceText, "$123.45")
    }

    func testSymbolInputNormalizesKRXCodeWithLeadingZeroes() {
        XCTAssertEqual(StockSymbolInput.normalizedSymbol(from: " 005930 "), "005930")
    }

    func testSymbolInputNormalizesUSTicker() {
        XCTAssertEqual(StockSymbolInput.normalizedSymbol(from: " brk.b "), "BRK.B")
    }

    func testSymbolInputRejectsInvalidNumericCode() {
        XCTAssertNil(StockSymbolInput.normalizedSymbol(from: "5930"))
    }

    func testPreferencesFallBackToDefaultSymbols() {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.\(UUID().uuidString)")!
        let preferences = StockerPreferences(defaults: defaults)

        XCTAssertEqual(preferences.registeredSymbols, MarketDataCatalog.symbols)
        XCTAssertTrue(MarketDataCatalog.symbols.contains(preferences.symbolForScreenSaverDisplay ?? ""))
    }
}
