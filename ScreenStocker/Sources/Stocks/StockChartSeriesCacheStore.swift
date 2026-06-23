import Foundation
import Darwin

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

    private static let suiteName = "com.tasokiii.ScreenStocker.marketDataCache"

    private let defaults: UserDefaults
    private let mirrorsSharedCache: Bool

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: StockChartSeriesCacheStore.suiteName) ?? .standard
        self.mirrorsSharedCache = defaults == nil
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

    func activeSessionEntry(
        for symbol: String,
        timeZoneIdentifier: String,
        referenceDate: Date = Date()
    ) -> IntradaySeriesCacheEntry? {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return nil
        }

        return entry(
            for: symbol,
            dayIdentifier: Self.activeSessionDayIdentifier(for: referenceDate, timeZone: timeZone),
            timeZoneIdentifier: timeZoneIdentifier,
            referenceDate: referenceDate
        )
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
        var mergedEntries: [String: IntradaySeriesCacheEntry] = [:]

        for entries in cacheEntrySources() {
            mergedEntries = Self.mergedEntries(mergedEntries, entries)
        }

        return mergedEntries.isEmpty ? nil : mergedEntries
    }

    private func store(entries: [String: IntradaySeriesCacheEntry]) {
        guard let data = try? PropertyListEncoder().encode(entries) else {
            return
        }
        defaults.set(data, forKey: Key.intradaySeriesCache)
        defaults.synchronize()

        guard mirrorsSharedCache else { return }
        for url in Self.sharedCacheURLs() {
            Self.updateCacheFile(at: url, data: data)
        }
    }

    private func cacheEntrySources() -> [[String: IntradaySeriesCacheEntry]] {
        var sources: [[String: IntradaySeriesCacheEntry]] = []

        if let data = defaults.data(forKey: Key.intradaySeriesCache),
           let entries = Self.decodeEntries(from: data) {
            sources.append(entries)
        }

        guard mirrorsSharedCache else { return sources }
        for url in Self.sharedCacheURLs() {
            guard let entries = Self.readCacheFile(at: url) else {
                continue
            }
            sources.append(entries)
        }

        return sources
    }

    private static func mergedEntries(
        _ existingEntries: [String: IntradaySeriesCacheEntry],
        _ newEntries: [String: IntradaySeriesCacheEntry]
    ) -> [String: IntradaySeriesCacheEntry] {
        var mergedEntries = existingEntries
        for (symbol, newEntry) in newEntries {
            guard let existingEntry = mergedEntries[symbol] else {
                mergedEntries[symbol] = newEntry
                continue
            }

            guard existingEntry.dayIdentifier == newEntry.dayIdentifier,
                  existingEntry.timeZoneIdentifier == newEntry.timeZoneIdentifier else {
                mergedEntries[symbol] = newerEntry(existingEntry, newEntry)
                continue
            }

            var candlesByTimestamp: [Date: IntradayCandle] = [:]
            for candle in existingEntry.candles {
                candlesByTimestamp[candle.timestamp] = candle
            }
            for candle in newEntry.candles {
                candlesByTimestamp[candle.timestamp] = candle
            }

            mergedEntries[symbol] = IntradaySeriesCacheEntry(
                symbol: symbol,
                dayIdentifier: existingEntry.dayIdentifier,
                timeZoneIdentifier: existingEntry.timeZoneIdentifier,
                isComplete: existingEntry.isComplete || newEntry.isComplete,
                candles: candlesByTimestamp.values.sorted { $0.timestamp < $1.timestamp }
            )
        }
        return mergedEntries
    }

    private static func newerEntry(
        _ lhs: IntradaySeriesCacheEntry,
        _ rhs: IntradaySeriesCacheEntry
    ) -> IntradaySeriesCacheEntry {
        let lhsTimestamp = lhs.candles.map(\.timestamp).max() ?? .distantPast
        let rhsTimestamp = rhs.candles.map(\.timestamp).max() ?? .distantPast
        return rhsTimestamp >= lhsTimestamp ? rhs : lhs
    }

    private static func decodeEntries(from data: Data) -> [String: IntradaySeriesCacheEntry]? {
        try? PropertyListDecoder().decode([String: IntradaySeriesCacheEntry].self, from: data)
    }

    private static func readCacheFile(at url: URL) -> [String: IntradaySeriesCacheEntry]? {
        guard let preferences = readPreferenceFile(at: url),
              let data = preferences[Key.intradaySeriesCache] as? Data else {
            return nil
        }
        return decodeEntries(from: data)
    }

    private static func updateCacheFile(at url: URL, data: Data) {
        updatePreferenceFile(at: url) { preferences in
            preferences[Key.intradaySeriesCache] = data
        }
    }

    private static func sharedCacheURLs() -> [URL] {
        var seen = Set<String>()
        return [hostCacheURL, screenSaverCacheURL]
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static var hostCacheURL: URL {
        realHomeDirectory
            .appendingPathComponent("Library/Preferences", isDirectory: true)
            .appendingPathComponent("\(suiteName).plist")
    }

    private static var screenSaverCacheURL: URL {
        realHomeDirectory
            .appendingPathComponent("Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Preferences", isDirectory: true)
            .appendingPathComponent("\(suiteName).plist")
    }

    private static var realHomeDirectory: URL {
        if let passwordEntry = getpwuid(getuid()),
           let homeDirectory = passwordEntry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: homeDirectory), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private static func readPreferenceFile(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let preferences = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any] else {
            return nil
        }
        return preferences
    }

    private static func updatePreferenceFile(
        at url: URL,
        update: (inout [String: Any]) -> Void
    ) {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            var preferences: [String: Any] = [:]
            if let storedPreferences = readPreferenceFile(at: url) {
                preferences = storedPreferences
            }

            update(&preferences)

            let data = try PropertyListSerialization.data(
                fromPropertyList: preferences,
                format: .binary,
                options: 0
            )
            try data.write(to: url, options: .atomic)
        } catch {}
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
