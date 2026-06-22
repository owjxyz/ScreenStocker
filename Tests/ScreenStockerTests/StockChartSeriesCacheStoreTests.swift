import Foundation
import XCTest

final class StockChartSeriesCacheStoreTests: XCTestCase {
    func testPrunesEntriesFromPreviousDayWhenTheDateChanges() {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.cache.\(UUID().uuidString)")!
        let store = StockChartSeriesCacheStore(defaults: defaults)
        let timeZone = TimeZone(identifier: "Asia/Seoul")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

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

        store.pruneStaleEntries(referenceDate: today)

        XCTAssertNil(
            store.entry(
                for: "005930",
                dayIdentifier: StockChartSeriesCacheStore.dayIdentifier(for: yesterday, timeZone: timeZone),
                timeZoneIdentifier: timeZone.identifier
            )
        )
    }

    func testKeepsCurrentDayEntryWhenPruning() {
        let defaults = UserDefaults(suiteName: "com.tasokiii.ScreenStocker.tests.cache.\(UUID().uuidString)")!
        let store = StockChartSeriesCacheStore(defaults: defaults)
        let timeZone = TimeZone(identifier: "America/New_York")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: Date())
        let dayIdentifier = StockChartSeriesCacheStore.dayIdentifier(for: today, timeZone: timeZone)

        store.save(
            candles: [
                IntradayCandle(
                    timestamp: today,
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
            dayIdentifier: dayIdentifier,
            timeZoneIdentifier: timeZone.identifier
        )

        store.pruneStaleEntries(referenceDate: today)

        XCTAssertNotNil(
            store.entry(
                for: "AAPL",
                dayIdentifier: dayIdentifier,
                timeZoneIdentifier: timeZone.identifier
            )
        )
    }
}
