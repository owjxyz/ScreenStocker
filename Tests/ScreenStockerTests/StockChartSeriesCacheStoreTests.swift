import Foundation
import XCTest

final class StockChartSeriesCacheStoreTests: XCTestCase {
    func testKeepsKRXPreviousDayEntryBeforeSeoulMarketOpen() {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.cache.\(UUID().uuidString)")!
        let store = StockChartSeriesCacheStore(defaults: defaults)
        let timeZone = TimeZone(identifier: "Asia/Seoul")!
        let yesterday = Self.date(year: 2026, month: 1, day: 15, hour: 15, timeZone: timeZone)
        let beforeMarketOpen = Self.date(year: 2026, month: 1, day: 16, hour: 7, minute: 59, timeZone: timeZone)

        store.save(
            candles: [
                IntradayCandle(
                    timestamp: yesterday,
                    openPrice: 100,
                    highPrice: 101,
                    lowPrice: 99,
                    closePrice: 100,
                    market: "KRX",
                    exchange: nil,
                    venue: nil
                )
            ],
            isComplete: true,
            for: "005930",
            dayIdentifier: StockChartSeriesCacheStore.dayIdentifier(for: yesterday, timeZone: timeZone),
            timeZoneIdentifier: timeZone.identifier
        )

        store.pruneStaleEntries(referenceDate: beforeMarketOpen)

        XCTAssertNotNil(
            store.entry(
                for: "005930",
                dayIdentifier: StockChartSeriesCacheStore.dayIdentifier(for: yesterday, timeZone: timeZone),
                timeZoneIdentifier: timeZone.identifier,
                referenceDate: beforeMarketOpen
            )
        )
    }

    func testPrunesKRXPreviousDayEntryAtSeoulMarketOpen() {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.cache.\(UUID().uuidString)")!
        let store = StockChartSeriesCacheStore(defaults: defaults)
        let timeZone = TimeZone(identifier: "Asia/Seoul")!
        let yesterday = Self.date(year: 2026, month: 1, day: 15, hour: 15, timeZone: timeZone)
        let marketOpen = Self.date(year: 2026, month: 1, day: 16, hour: 8, timeZone: timeZone)

        store.save(
            candles: [
                IntradayCandle(
                    timestamp: yesterday,
                    openPrice: 100,
                    highPrice: 101,
                    lowPrice: 99,
                    closePrice: 100,
                    market: "KRX",
                    exchange: nil,
                    venue: nil
                )
            ],
            isComplete: true,
            for: "005930",
            dayIdentifier: StockChartSeriesCacheStore.dayIdentifier(for: yesterday, timeZone: timeZone),
            timeZoneIdentifier: timeZone.identifier
        )

        store.pruneStaleEntries(referenceDate: marketOpen)

        XCTAssertNil(
            store.entry(
                for: "005930",
                dayIdentifier: StockChartSeriesCacheStore.dayIdentifier(for: yesterday, timeZone: timeZone),
                timeZoneIdentifier: timeZone.identifier,
                referenceDate: marketOpen
            )
        )
    }

    func testKeepsUSPreviousDayEntryBeforeNewYorkMarketOpen() {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.cache.\(UUID().uuidString)")!
        let store = StockChartSeriesCacheStore(defaults: defaults)
        let timeZone = TimeZone(identifier: "America/New_York")!
        let yesterday = Self.date(year: 2026, month: 1, day: 15, hour: 16, timeZone: timeZone)
        let beforeMarketOpen = Self.date(year: 2026, month: 1, day: 16, hour: 3, minute: 59, timeZone: timeZone)

        store.save(
            candles: [
                IntradayCandle(
                    timestamp: yesterday,
                    openPrice: 100,
                    highPrice: 101,
                    lowPrice: 99,
                    closePrice: 100,
                    market: "US",
                    exchange: nil,
                    venue: nil
                )
            ],
            isComplete: true,
            for: "AAPL",
            dayIdentifier: StockChartSeriesCacheStore.dayIdentifier(for: yesterday, timeZone: timeZone),
            timeZoneIdentifier: timeZone.identifier
        )

        store.pruneStaleEntries(referenceDate: beforeMarketOpen)

        XCTAssertNotNil(
            store.entry(
                for: "AAPL",
                dayIdentifier: StockChartSeriesCacheStore.dayIdentifier(for: yesterday, timeZone: timeZone),
                timeZoneIdentifier: timeZone.identifier,
                referenceDate: beforeMarketOpen
            )
        )
    }

    func testPrunesUSPreviousDayEntryAtNewYorkMarketOpen() {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.cache.\(UUID().uuidString)")!
        let store = StockChartSeriesCacheStore(defaults: defaults)
        let timeZone = TimeZone(identifier: "America/New_York")!
        let yesterday = Self.date(year: 2026, month: 1, day: 15, hour: 16, timeZone: timeZone)
        let marketOpen = Self.date(year: 2026, month: 1, day: 16, hour: 4, timeZone: timeZone)

        store.save(
            candles: [
                IntradayCandle(
                    timestamp: yesterday,
                    openPrice: 100,
                    highPrice: 101,
                    lowPrice: 99,
                    closePrice: 100,
                    market: "US",
                    exchange: nil,
                    venue: nil
                )
            ],
            isComplete: true,
            for: "AAPL",
            dayIdentifier: StockChartSeriesCacheStore.dayIdentifier(for: yesterday, timeZone: timeZone),
            timeZoneIdentifier: timeZone.identifier
        )

        store.pruneStaleEntries(referenceDate: marketOpen)

        XCTAssertNil(
            store.entry(
                for: "AAPL",
                dayIdentifier: StockChartSeriesCacheStore.dayIdentifier(for: yesterday, timeZone: timeZone),
                timeZoneIdentifier: timeZone.identifier,
                referenceDate: marketOpen
            )
        )
    }

    func testKeepsFridayEntryOverWeekendUntilNextUSMarketOpen() {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.cache.\(UUID().uuidString)")!
        let store = StockChartSeriesCacheStore(defaults: defaults)
        let timeZone = TimeZone(identifier: "America/New_York")!
        let friday = Self.date(year: 2026, month: 1, day: 16, hour: 16, timeZone: timeZone)
        let mondayBeforeMarketOpen = Self.date(year: 2026, month: 1, day: 19, hour: 3, minute: 59, timeZone: timeZone)

        store.save(
            candles: [
                IntradayCandle(
                    timestamp: friday,
                    openPrice: 100,
                    highPrice: 101,
                    lowPrice: 99,
                    closePrice: 100,
                    market: "US",
                    exchange: nil,
                    venue: nil
                )
            ],
            isComplete: true,
            for: "AAPL",
            dayIdentifier: StockChartSeriesCacheStore.dayIdentifier(for: friday, timeZone: timeZone),
            timeZoneIdentifier: timeZone.identifier
        )

        store.pruneStaleEntries(referenceDate: mondayBeforeMarketOpen)

        XCTAssertNotNil(
            store.entry(
                for: "AAPL",
                dayIdentifier: StockChartSeriesCacheStore.dayIdentifier(for: friday, timeZone: timeZone),
                timeZoneIdentifier: timeZone.identifier,
                referenceDate: mondayBeforeMarketOpen
            )
        )
    }

    private static func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0,
        timeZone: TimeZone
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(
            from: DateComponents(
                timeZone: timeZone,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }
}
