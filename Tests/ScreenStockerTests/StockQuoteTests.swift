import XCTest

final class StockQuoteTests: XCTestCase {
    func testDemoProviderReturnsConfiguredSymbols() {
        let provider = DemoStockQuoteProvider(symbols: ["005930", "000660"])
        let expectation = expectation(description: "quotes")

        provider.fetchQuotes { quotes in
            XCTAssertEqual(quotes.map(\.symbol), ["005930", "000660"])
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    func testKoreaInvestmentProviderDecodesQuote() throws {
        let data = try XCTUnwrap("""
        {
          "rt_cd": "0",
          "output": {
            "stck_prpr": "70000",
            "prdy_ctrt": "1.24",
            "hts_kor_isnm": "Samsung Electronics"
          }
        }
        """.data(using: .utf8))

        let quote = KoreaInvestmentQuoteProvider.decodeQuote(from: data, requestedSymbol: "005930")

        XCTAssertEqual(quote, StockQuote(symbol: "005930", price: Decimal(string: "70000")!, changePercent: Decimal(string: "1.24")!))
    }

    func testKoreaInvestmentSymbolSearchDecodesQuoteName() throws {
        let data = try XCTUnwrap("""
        {
          "rt_cd": "0",
          "output": {
            "stck_prpr": "70000",
            "prdy_ctrt": "1.24",
            "hts_kor_isnm": "Samsung Electronics"
          }
        }
        """.data(using: .utf8))

        let result = KoreaInvestmentSymbolSearchProvider.decodeSearchResult(from: data, requestedSymbol: "005930")

        XCTAssertEqual(
            result,
            StockSymbolSearchResult(
                symbol: "005930",
                name: "Samsung Electronics",
                exchange: "KRX",
                country: "KR",
                currency: "KRW",
                type: nil
            )
        )
    }

    func testKoreaInvestmentProviderDecodesTimeSeriesInChronologicalOrder() throws {
        let data = try XCTUnwrap("""
        {
          "rt_cd": "0",
          "output2": [
            {
              "stck_bsop_date": "20260508",
              "stck_clpr": "70500"
            },
            {
              "stck_bsop_date": "20260507",
              "stck_clpr": "69800"
            }
          ]
        }
        """.data(using: .utf8))

        let series = try XCTUnwrap(KoreaInvestmentTimeSeriesProvider.decodeTimeSeries(from: data, requestedSymbol: "005930"))

        XCTAssertEqual(series.symbol, "005930")
        XCTAssertEqual(series.points.map(\.close), [Decimal(string: "69800")!, Decimal(string: "70500")!])
    }
}
