import XCTest

final class StockQuoteTests: XCTestCase {
    func testMarketDataReturnsSelectedQuote() {
        let quote = MarketDataCatalog.quote(for: "000660")

        XCTAssertEqual(quote.symbol, "000660")
        XCTAssertEqual(quote.changePercent, Decimal(string: "-0.82")!)
    }

    func testMarketChartSeriesUsesSelectedSymbol() {
        let series = MarketDataCatalog.chartSeries(for: "035420")

        XCTAssertEqual(series.symbol, "035420")
        XCTAssertGreaterThan(series.points.count, 2)
        XCTAssertNotNil(series.highClose)
        XCTAssertNotNil(series.lowClose)
    }

    func testPreferencesFallBackToDefaultSymbols() {
        let defaults = UserDefaults(suiteName: "com.lukeoh.ScreenStocker.tests.\(UUID().uuidString)")!
        let preferences = StockerPreferences(defaults: defaults)

        XCTAssertEqual(preferences.registeredSymbols, MarketDataCatalog.symbols)
        XCTAssertEqual(preferences.symbolForScreenSaverDisplay, MarketDataCatalog.symbols.first)
    }
}
