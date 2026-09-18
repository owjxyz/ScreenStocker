import Foundation
import XCTest

final class StockMarketCalendarTests: XCTestCase {
    func testUSKSTTimestampsSelectNextBusinessDayBeforeNewYorkMidnight() throws {
        let response = MarketCalendarTestData.calendar(country: "US", day: "2026-03-24")
        try response.validate(country: "US", queryDay: "2026-03-24")
        let cache = StockMarketCalendarCache(queryDay: "2026-03-24", fetchedAt: Date(), days: response.days)
        let group = try XCTUnwrap(cache.group(country: "US", at: date("2026-03-25T09:10:00+09:00")))
        XCTAssertTrue(group.isDayMarket)
        XCTAssertEqual(group.day, "2026-03-25")
        XCTAssertEqual(group.end, date("2026-03-25T16:50:00+09:00"))
        let breakGroup = cache.group(country: "US", at: date("2026-03-25T16:55:00+09:00"))
        XCTAssertEqual(breakGroup?.freshnessReference(at: date("2026-03-25T16:55:00+09:00")), group.end)
        XCTAssertEqual(cache.group(country: "US", at: date("2026-03-25T17:00:00+09:00"))?.isDayMarket, false)
    }

    func testUSWinterAndSummerUseResponseOffsets() {
        for (day, expectedHour) in [("2026-01-16", "23"), ("2026-03-25", "22")] {
            let response = MarketCalendarTestData.calendar(country: "US", day: day)
            XCTAssertEqual(response.today.regularMarket?.startTime, date("\(day)T\(expectedHour):30:00+09:00"))
        }
    }

    func testHolidayAndPartialClosureRemainDifferentFromMissingCalendar() throws {
        let response = MarketCalendarTestData.calendar(country: "KR", day: "2026-05-05")
        XCTAssertTrue(response.today.groups(country: "KR").isEmpty)
        XCTAssertEqual(response.previousBusinessDay.date, "2026-05-04")
        let cache = StockMarketCalendarCache(queryDay: "2026-05-05", fetchedAt: Date(), days: response.days)
        XCTAssertEqual(cache.group(country: "KR", at: date("2026-05-05T12:00:00+09:00"))?.day, "2026-05-04")
        XCTAssertNil(cache.group(country: "KR", at: date("2026-05-20T12:00:00+09:00")))
        var partial = MarketCalendarTestData.calendar(country: "KR", day: "2026-03-25").today
        partial.integrated?.preMarket = nil
        let group = try XCTUnwrap(partial.groups(country: "KR").first)
        XCTAssertEqual(group.start, date("2026-03-25T09:00:00+09:00"))
        XCTAssertEqual(group.sessions[0].continuousInterval?.end, date("2026-03-25T15:20:00+09:00"))
        XCTAssertEqual(group.sessions[1].continuousInterval?.start, date("2026-03-25T15:40:00+09:00"))
    }

    func testInvalidHoursAreRejectedAndEarlyCloseIsPreserved() throws {
        let response = MarketCalendarTestData.calendar(country: "US", day: "2026-03-25")
        var today = response.today
        today.regularMarket = .init(startTime: date("2026-03-25T22:30:00+09:00"), endTime: date("2026-03-26T02:00:00+09:00"))
        today.afterMarket = nil
        let earlyClose = StockMarketCalendar(today: today, previousBusinessDay: response.previousBusinessDay, nextBusinessDay: response.nextBusinessDay)
        try earlyClose.validate(country: "US", queryDay: "2026-03-25")
        XCTAssertEqual(today.groups(country: "US").last?.end, date("2026-03-26T02:00:00+09:00"))
        today.regularMarket = .init(startTime: date("2026-03-26T02:00:00+09:00"), endTime: date("2026-03-25T22:30:00+09:00"))
        XCTAssertThrowsError(try StockMarketCalendar(today: today, previousBusinessDay: response.previousBusinessDay, nextBusinessDay: response.nextBusinessDay).validate(country: "US", queryDay: "2026-03-25"))
    }

    func testRefreshCoalescesPersistsExpiresAndPreservesCacheOnFailure() async throws {
        let suite = "com.tasokiii.ScreenStocker.tests.calendar.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = StockChartSeriesCacheStore(defaults: defaults)
        let refresh = StockMarketCalendarRefresh()
        let counter = CalendarFetchCounter()
        let now = date("2026-03-25T12:00:00+09:00")
        let fetch: () async throws -> StockMarketCalendar = {
            await counter.increment()
            try await Task.sleep(nanoseconds: 10_000_000)
            return MarketCalendarTestData.calendar(country: "KR", day: "2026-03-25")
        }
        async let first: Void = refresh.refresh(country: "KR", queryDay: "2026-03-25", now: now, store: store, fetch: fetch)
        async let second: Void = refresh.refresh(country: "KR", queryDay: "2026-03-25", now: now, store: store, fetch: fetch)
        _ = await (first, second)
        let count = await counter.value
        XCTAssertEqual(count, 1)
        let reloadedStore = StockChartSeriesCacheStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.marketCalendar(country: "KR")?.queryDay, "2026-03-25")
        await refresh.refresh(country: "KR", queryDay: "2026-03-25", now: now.addingTimeInterval(60), store: store, fetch: fetch)
        let cachedCount = await counter.value
        XCTAssertEqual(cachedCount, 1)
        let failedFetch: () async throws -> StockMarketCalendar = {
            await counter.increment()
            throw URLError(.notConnectedToInternet)
        }
        for offset in [3_600.0, 3_660.0] {
            await refresh.refresh(country: "KR", queryDay: "2026-03-25", now: now.addingTimeInterval(offset), store: store, fetch: failedFetch)
        }
        let failureCount = await counter.value
        XCTAssertEqual(failureCount, 2)
        XCTAssertEqual(store.marketCalendar(country: "KR")?.fetchedAt, now)
        await refresh.refresh(country: "KR", queryDay: "2026-03-26", now: now.addingTimeInterval(3_700), store: store) {
            MarketCalendarTestData.calendar(country: "KR", day: "2026-03-26")
        }
        XCTAssertEqual(store.marketCalendar(country: "KR")?.queryDay, "2026-03-26")
    }

    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
}

private actor CalendarFetchCounter {
    var value = 0
    func increment() { value += 1 }
}

// Deterministic mock server data. Times live only in tests; production consumes the API.
enum MarketCalendarTestData {
    static func calendar(country: String, day: String) -> StockMarketCalendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: country == "US" ? "America/New_York" : "Asia/Seoul")!
        let parts = day.split(separator: "-").map { Int($0)! }
        let requested = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
        func identifier(_ date: Date) -> String {
            StockChartSeriesCacheStore.dayIdentifier(for: date, timeZone: calendar.timeZone)
        }
        func closed(_ date: Date) -> Bool {
            calendar.isDateInWeekend(date) || (country == "US" ? ["2026-07-03"] : ["2026-05-05"]).contains(identifier(date))
        }
        func businessDay(direction: Int) -> Date {
            var date = calendar.date(byAdding: .day, value: direction, to: requested)!
            while closed(date) { date = calendar.date(byAdding: .day, value: direction, to: date)! }
            return date
        }
        func marketDay(_ date: Date) -> StockMarketCalendar.Day {
            let name = identifier(date)
            if closed(date) { return .init(date: name) }
            func time(_ hour: Int, _ minute: Int = 0) -> Date {
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
            }
            if country == "KR" {
                return .init(date: name, integrated: .init(
                    preMarket: .init(startTime: time(8), endTime: time(9), singlePriceAuctionStartTime: time(8, 50)),
                    regularMarket: .init(startTime: time(9), endTime: time(15, 30), singlePriceAuctionStartTime: time(15, 20)),
                    afterMarket: .init(startTime: time(15, 30), endTime: time(20), singlePriceAuctionEndTime: time(15, 40))))
            }
            let previous = calendar.date(byAdding: .day, value: -1, to: date)!
            let start = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: previous)!
            return .init(date: name,
                         dayMarket: .init(startTime: start, endTime: time(3, 50)),
                         preMarket: .init(startTime: time(4), endTime: time(9, 30)),
                         regularMarket: .init(startTime: time(9, 30), endTime: time(16)),
                         afterMarket: .init(startTime: time(16), endTime: time(18)))
        }
        return .init(today: marketDay(requested), previousBusinessDay: marketDay(businessDay(direction: -1)), nextBusinessDay: marketDay(businessDay(direction: 1)))
    }

    static func response(country: String, day: String) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try! encoder.encode(["result": calendar(country: country, day: day)])
    }
}
