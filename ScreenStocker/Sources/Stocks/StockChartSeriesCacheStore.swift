import Foundation

struct IntradayCandle: Codable, Equatable {
    let timestamp: Date
    let openPrice: Decimal
    let highPrice: Decimal?
    let lowPrice: Decimal?
    let closePrice: Decimal
    let market: String?
    let exchange: String?
    let venue: String?
}

struct IntradaySeriesCacheEntry: Codable, Equatable {
    let symbol: String
    let dayIdentifier: String
    let timeZoneIdentifier: String
    var isComplete: Bool
    var candles: [IntradayCandle]
}

final class StockChartSeriesCacheStore {
    private enum Key {
        static let intradaySeriesCache = "intradaySeriesCache"
    }

    private static let suiteName = "com.tasokiii.ScreenStocker.preferences"

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: StockChartSeriesCacheStore.suiteName)) {
        self.defaults = defaults ?? .standard
        pruneStaleEntries()
    }

    func entry(
        for symbol: String,
        dayIdentifier: String,
        timeZoneIdentifier: String,
        referenceDate: Date = Date()
    ) -> IntradaySeriesCacheEntry? {
        pruneStaleEntries(referenceDate: referenceDate)
        guard let entries = loadEntries(),
              let entry = entries[symbol],
              entry.dayIdentifier == dayIdentifier,
              entry.timeZoneIdentifier == timeZoneIdentifier else {
            return nil
        }
        return entry
    }

    func save(
        candles: [IntradayCandle],
        isComplete: Bool,
        for symbol: String,
        dayIdentifier: String,
        timeZoneIdentifier: String,
        referenceDate: Date = Date()
    ) {
        pruneStaleEntries(referenceDate: referenceDate)
        var entries = loadEntries() ?? [:]
        entries[symbol] = IntradaySeriesCacheEntry(
            symbol: symbol,
            dayIdentifier: dayIdentifier,
            timeZoneIdentifier: timeZoneIdentifier,
            isComplete: isComplete,
            candles: candles.sorted(by: { $0.timestamp < $1.timestamp })
        )
        store(entries: entries)
    }

    func pruneStaleEntries(referenceDate: Date = Date()) {
        guard var entries = loadEntries() else { return }

        let filteredEntries = entries.filter { _, entry in
            guard let timeZone = TimeZone(identifier: entry.timeZoneIdentifier) else {
                return false
            }

            return entry.dayIdentifier == Self.activeSessionDayIdentifier(
                for: referenceDate,
                timeZone: timeZone
            )
        }

        guard filteredEntries.count != entries.count else { return }
        entries = filteredEntries
        store(entries: entries)
    }

    private func loadEntries() -> [String: IntradaySeriesCacheEntry]? {
        guard let data = defaults.data(forKey: Key.intradaySeriesCache) else {
            return nil
        }
        return try? PropertyListDecoder().decode([String: IntradaySeriesCacheEntry].self, from: data)
    }

    private func store(entries: [String: IntradaySeriesCacheEntry]) {
        guard let data = try? PropertyListEncoder().encode(entries) else {
            return
        }
        defaults.set(data, forKey: Key.intradaySeriesCache)
        defaults.synchronize()
    }

    static func dayIdentifier(for date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func activeSessionDayIdentifier(for date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let rolloverTime = cacheRolloverTime(for: timeZone)
        let rolloverDate = calendar.date(
            bySettingHour: rolloverTime.hour,
            minute: rolloverTime.minute,
            second: 0,
            of: date
        ) ?? calendar.startOfDay(for: date)

        var activeSessionDate = date
        if date < rolloverDate,
           let previousDay = calendar.date(byAdding: .day, value: -1, to: activeSessionDate) {
            activeSessionDate = previousDay
        }

        while calendar.isDateInWeekend(activeSessionDate),
              let previousDay = calendar.date(byAdding: .day, value: -1, to: activeSessionDate) {
            activeSessionDate = previousDay
        }

        return dayIdentifier(for: activeSessionDate, timeZone: timeZone)
    }

    private static func cacheRolloverTime(for timeZone: TimeZone) -> (hour: Int, minute: Int) {
        switch timeZone.identifier {
        case "Asia/Seoul":
            return (8, 0)
        case "America/New_York":
            return (4, 0)
        default:
            return (0, 0)
        }
    }
}
