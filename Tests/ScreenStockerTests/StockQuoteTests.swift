import XCTest

final class StockQuoteTests: XCTestCase {
    func testDemoProviderReturnsConfiguredSymbols() {
        let provider = DemoStockQuoteProvider(symbols: ["AAPL", "MSFT"])
        let expectation = expectation(description: "quotes")

        provider.fetchQuotes { quotes in
            XCTAssertEqual(quotes.map(\.symbol), ["AAPL", "MSFT"])
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testTwelveDataProviderDecodesSingleQuote() throws {
        let data = try XCTUnwrap("""
        {
          "symbol": "AAPL",
          "close": "182.52",
          "percent_change": "1.24"
        }
        """.data(using: .utf8))

        let quotes = TwelveDataQuoteProvider.decodeQuotes(from: data, requestedSymbols: ["AAPL"])

        XCTAssertEqual(quotes, [StockQuote(symbol: "AAPL", price: Decimal(string: "182.52")!, changePercent: Decimal(string: "1.24")!)])
    }

    func testTwelveDataProviderDecodesBatchQuotesInRequestedOrder() throws {
        let data = try XCTUnwrap("""
        {
          "MSFT": {
            "symbol": "MSFT",
            "close": "410.10",
            "percent_change": "-0.32"
          },
          "AAPL": {
            "symbol": "AAPL",
            "close": "182.52",
            "percent_change": "1.24"
          }
        }
        """.data(using: .utf8))

        let quotes = TwelveDataQuoteProvider.decodeQuotes(from: data, requestedSymbols: ["AAPL", "MSFT"])

        XCTAssertEqual(quotes.map(\.symbol), ["AAPL", "MSFT"])
    }

    func testTwelveDataProviderDecodesTimeSeriesInChronologicalOrder() throws {
        let data = try XCTUnwrap("""
        {
          "meta": {
            "symbol": "AAPL"
          },
          "values": [
            {
              "datetime": "2026-05-08",
              "close": "183.25"
            },
            {
              "datetime": "2026-05-07",
              "close": "181.40"
            }
          ],
          "status": "ok"
        }
        """.data(using: .utf8))

        let series = try XCTUnwrap(TwelveDataTimeSeriesProvider.decodeTimeSeries(from: data, requestedSymbol: "AAPL"))

        XCTAssertEqual(series.symbol, "AAPL")
        XCTAssertEqual(series.points.map(\.close), [Decimal(string: "181.40")!, Decimal(string: "183.25")!])
    }
}
