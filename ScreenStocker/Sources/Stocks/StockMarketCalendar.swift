import Foundation

// Dates identify exchange business days; session timestamps are absolute instants,
// including the KST offset returned by both Toss calendar endpoints.
struct StockMarketCalendar: Codable {
    struct Session: Codable {
        let startTime: Date
        let endTime: Date
        var singlePriceAuctionStartTime: Date?
        var singlePriceAuctionEndTime: Date?

        var isValid: Bool {
            startTime < endTime
                && [singlePriceAuctionStartTime, singlePriceAuctionEndTime].compactMap { $0 }
                    .allSatisfy { $0 >= startTime && $0 <= endTime }
        }

        var continuousInterval: DateInterval? {
            let start = singlePriceAuctionEndTime ?? startTime
            let end = singlePriceAuctionStartTime ?? endTime
            return start < end ? DateInterval(start: start, end: end) : nil
        }
    }

    struct IntegratedHours: Codable {
        var preMarket: Session?
        var regularMarket: Session?
        var afterMarket: Session?
    }

    struct Day: Codable {
        let date: String
        var integrated: IntegratedHours?
        var dayMarket: Session?
        var preMarket: Session?
        var regularMarket: Session?
        var afterMarket: Session?

        func groups(country: String) -> [Group] {
            if country == "KR" {
                let sessions = [integrated?.preMarket, integrated?.regularMarket, integrated?.afterMarket]
                    .compactMap { $0 }
                return sessions.isEmpty ? [] : [Group(day: date, isDayMarket: false, sessions: sessions)]
            }
            let sessions = [preMarket, regularMarket, afterMarket].compactMap { $0 }
            return (dayMarket.map { [Group(day: date, isDayMarket: true, sessions: [$0])] } ?? [])
                + (sessions.isEmpty ? [] : [Group(day: date, isDayMarket: false, sessions: sessions)])
        }
    }

    struct Group {
        let day: String
        let isDayMarket: Bool
        let sessions: [Session]

        var start: Date { sessions[0].startTime }
        var end: Date { sessions[sessions.count - 1].endTime }
        var dividers: [Date] { sessions.dropFirst().map(\.startTime) }

        func containsCandle(at date: Date) -> Bool {
            sessions.contains { date >= $0.startTime && date <= $0.endTime }
        }

        func freshnessReference(at date: Date) -> Date? {
            sessions.filter { $0.startTime <= date }.last.map { min(date, $0.endTime) }
        }
    }

    let today: Day
    let previousBusinessDay: Day
    let nextBusinessDay: Day

    var days: [Day] { [previousBusinessDay, today, nextBusinessDay] }

    func validate(country: String, queryDay: String) throws {
        guard today.date == queryDay,
              previousBusinessDay.date < today.date, today.date < nextBusinessDay.date,
              days.allSatisfy({ day in
                  let formatter = DateFormatter()
                  formatter.locale = Locale(identifier: "en_US_POSIX")
                  formatter.timeZone = TimeZone(secondsFromGMT: 0)
                  formatter.dateFormat = "yyyy-MM-dd"
                  formatter.isLenient = false
                  guard let date = formatter.date(from: day.date),
                        formatter.string(from: date) == day.date else { return false }
                  let groups = day.groups(country: country)
                  return groups.allSatisfy { group in
                      group.sessions.allSatisfy(\.isValid)
                          && zip(group.sessions, group.sessions.dropFirst()).allSatisfy {
                              $0.endTime <= $1.startTime
                          }
                  } && zip(groups, groups.dropFirst()).allSatisfy { $0.end <= $1.start }
              }) else {
            throw TossInvestMarketDataError.invalidResponse
        }
    }
}

struct StockMarketCalendarCache: Codable {
    let queryDay: String
    let fetchedAt: Date
    let days: [StockMarketCalendar.Day]

    func groups(country: String) -> [StockMarketCalendar.Group] {
        days.flatMap { $0.groups(country: country) }.sorted { $0.start < $1.start }
    }

    func group(country: String, at date: Date, isDayMarket: Bool? = nil) -> StockMarketCalendar.Group? {
        let groups = groups(country: country)
        let zone = TimeZone(identifier: country == "US" ? "America/New_York" : "Asia/Seoul")!
        let localDay = StockChartSeriesCacheStore.dayIdentifier(for: date, timeZone: zone)
        guard days.contains(where: { $0.date == localDay }) || groups.contains(where: { $0.containsCandle(at: date) }) else {
            return nil
        }
        return groups.last {
            $0.start <= date && (isDayMarket == nil || $0.isDayMarket == isDayMarket)
        }
    }
}

// One refresh per market per client; callers share the request while disk storage
// shares successful calendars between the management app and saver processes.
actor StockMarketCalendarRefresh {
    private var tasks: [String: Task<Void, Never>] = [:]
    private var retryAfter: [String: Date] = [:]

    func refresh(
        country: String,
        queryDay: String,
        now: Date,
        store: StockChartSeriesCacheStore,
        fetch: @escaping () async throws -> StockMarketCalendar
    ) async {
        let retryKey = "\(country)|\(queryDay)"
        if let task = tasks[retryKey] {
            await task.value
            return
        }
        if let cache = store.marketCalendar(country: country),
           cache.queryDay == queryDay, now >= cache.fetchedAt,
           now.timeIntervalSince(cache.fetchedAt) < 3_600 {
            return
        }
        guard retryAfter[retryKey].map({ now < $0 }) != true else { return }
        retryAfter = retryAfter.filter { $0.value > now }
        let task = Task {
            do {
                let calendar = try await fetch()
                try calendar.validate(country: country, queryDay: queryDay)
                store.saveMarketCalendar(calendar, country: country, queryDay: queryDay, fetchedAt: now)
            } catch {
                // A failed request is unknown, never a synthetic closed day.
                self.retryAfter[retryKey] = now.addingTimeInterval(300)
            }
        }
        tasks[retryKey] = task
        await task.value
        tasks[retryKey] = nil
    }
}
