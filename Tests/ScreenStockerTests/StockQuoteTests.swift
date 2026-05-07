import XCTest
@testable import ScreenStocker

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
}
