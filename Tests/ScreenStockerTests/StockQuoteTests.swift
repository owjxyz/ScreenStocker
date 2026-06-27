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
        let quote = StockQuote(symbol: "005930", displayName: nil, exchangeLabel: nil, price: Decimal(75300), changePercent: nil, currency: "KRW")

        XCTAssertEqual(quote.priceText, "₩75,300")
    }

    func testUSDPriceTextKeepsFractionDigits() {
        let quote = StockQuote(symbol: "AAPL", displayName: nil, exchangeLabel: nil, price: Decimal(string: "123.45"), changePercent: nil, currency: "USD")

        XCTAssertEqual(quote.priceText, "$123.45")
    }

    func testPositiveChangePercentTextIncludesPlusSign() {
        let quote = StockQuote(symbol: "AAPL", displayName: nil, exchangeLabel: nil, price: nil, changePercent: Decimal(string: "1.23"))

        XCTAssertEqual(quote.changePercentText, "+1.23%")
    }

    func testNegativeChangePercentTextKeepsMinusSign() {
        let quote = StockQuote(symbol: "AAPL", displayName: nil, exchangeLabel: nil, price: nil, changePercent: Decimal(string: "-1.23"))

        XCTAssertEqual(quote.changePercentText, "-1.23%")
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

    func testNormalizedPointsUseSessionProgressInsteadOfFillingWidth() {
        let sessionStart = Date(timeIntervalSince1970: 1_700_000_000)
        let sessionEnd = sessionStart.addingTimeInterval(6 * 60 * 60)
        let series = StockChartSeries(
            symbol: "TEST",
            points: [
                StockTimeSeriesPoint(date: sessionStart, close: 100),
                StockTimeSeriesPoint(date: sessionStart.addingTimeInterval(60 * 60), close: 110),
                StockTimeSeriesPoint(date: sessionStart.addingTimeInterval(2 * 60 * 60), close: 120)
            ],
            sessionStart: sessionStart,
            sessionEnd: sessionEnd
        )

        let points = StockChartGeometry.normalizedPoints(for: series, in: CGSize(width: 600, height: 300))

        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(Double(points[0].x), 0, accuracy: 0.1)
        XCTAssertEqual(Double(points[1].x), 100, accuracy: 0.1)
        XCTAssertEqual(Double(points[2].x), 200, accuracy: 0.1)
    }

    func testRecommendedCandleWidthTracksSessionLength() {
        let sessionStart = Date(timeIntervalSince1970: 1_700_000_000)
        let sessionEnd = sessionStart.addingTimeInterval(6 * 60 * 60)
        let series = StockChartSeries(
            symbol: "TEST",
            points: [
                StockTimeSeriesPoint(date: sessionStart, close: 100),
                StockTimeSeriesPoint(date: sessionStart.addingTimeInterval(10 * 60), close: 102)
            ],
            sessionStart: sessionStart,
            sessionEnd: sessionEnd
        )

        let width = StockChartGeometry.recommendedCandleWidth(for: series, in: CGSize(width: 600, height: 300))

        XCTAssertEqual(Double(width), 13.333, accuracy: 0.2)
    }

    func testNormalizedCandlesUseBucketCenterPosition() {
        let sessionStart = Date(timeIntervalSince1970: 1_700_000_000)
        let sessionEnd = sessionStart.addingTimeInterval(60 * 60)
        let series = StockChartSeries(
            symbol: "TEST",
            points: [
                StockTimeSeriesPoint(date: sessionStart.addingTimeInterval(10 * 60), close: 100),
                StockTimeSeriesPoint(date: sessionStart.addingTimeInterval(20 * 60), close: 102)
            ],
            sessionStart: sessionStart,
            sessionEnd: sessionEnd
        )

        let candles = StockChartGeometry.normalizedCandles(for: series, in: CGSize(width: 600, height: 300))

        XCTAssertEqual(candles.count, 2)
        XCTAssertEqual(Double(candles[0].x), 50, accuracy: 0.1)
        XCTAssertEqual(Double(candles[1].x), 150, accuracy: 0.1)
    }

    func testCandlesCenterAroundSessionBoundaryWithoutMovingDivider() {
        let sessionStart = Date(timeIntervalSince1970: 1_700_000_000)
        let sessionEnd = sessionStart.addingTimeInterval(16 * 60 * 60)
        let regularOpen = sessionStart.addingTimeInterval(5.5 * 60 * 60)
        let firstRegularBucketEnd = regularOpen.addingTimeInterval(10 * 60)
        let series = StockChartSeries(
            symbol: "AAPL",
            points: [
                StockTimeSeriesPoint(date: regularOpen, close: 100),
                StockTimeSeriesPoint(date: firstRegularBucketEnd, close: 102)
            ],
            sessionStart: sessionStart,
            sessionEnd: sessionEnd,
            sessionDividers: [regularOpen]
        )

        let candles = StockChartGeometry.normalizedCandles(for: series, in: CGSize(width: 600, height: 300))
        let openX = StockChartGeometry.normalizedXPosition(for: regularOpen, in: series, size: CGSize(width: 600, height: 300))
        let expectedHalfBucketWidth = 600 * (5.0 * 60.0 / (16.0 * 60.0 * 60.0))

        XCTAssertEqual(Double(candles[1].x), Double(openX) + expectedHalfBucketWidth, accuracy: 0.1)
        XCTAssertEqual(Double(openX), 206.25, accuracy: 0.1)
    }

    func testNormalizedXPositionUsesExtendedTradingHoursForUSSeries() {
        let sessionStart = Date(timeIntervalSince1970: 1_700_000_000)
        let sessionEnd = sessionStart.addingTimeInterval(16 * 60 * 60)
        let regularOpen = sessionStart.addingTimeInterval(5.5 * 60 * 60)
        let regularClose = sessionStart.addingTimeInterval(12 * 60 * 60)
        let series = StockChartSeries(
            symbol: "AAPL",
            points: [
                StockTimeSeriesPoint(date: sessionStart, close: 100),
                StockTimeSeriesPoint(date: regularOpen, close: 102),
                StockTimeSeriesPoint(date: regularClose, close: 104)
            ],
            sessionStart: sessionStart,
            sessionEnd: sessionEnd,
            sessionDividers: [regularOpen, regularClose]
        )

        let openX = StockChartGeometry.normalizedXPosition(for: regularOpen, in: series, size: CGSize(width: 600, height: 300))
        let closeX = StockChartGeometry.normalizedXPosition(for: regularClose, in: series, size: CGSize(width: 600, height: 300))

        XCTAssertEqual(Double(openX), 206.25, accuracy: 0.1)
        XCTAssertEqual(Double(closeX), 450, accuracy: 0.1)
        XCTAssertEqual(series.sessionDividers.count, 2)
    }
}
