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
    let sessionIdentifier: String
    var isComplete: Bool
    var candles: [IntradayCandle]

    init(
        symbol: String,
        dayIdentifier: String,
        timeZoneIdentifier: String,
        sessionIdentifier: String = StockChartSeriesCacheStore.defaultSessionIdentifier,
        isComplete: Bool,
        candles: [IntradayCandle]
    ) {
        self.symbol = symbol
        self.dayIdentifier = dayIdentifier
        self.timeZoneIdentifier = timeZoneIdentifier
        self.sessionIdentifier = sessionIdentifier
        self.isComplete = isComplete
        self.candles = candles
    }

    private enum CodingKeys: String, CodingKey {
        case symbol
        case dayIdentifier
        case timeZoneIdentifier
        case sessionIdentifier
        case isComplete
        case candles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try container.decode(String.self, forKey: .symbol)
        dayIdentifier = try container.decode(String.self, forKey: .dayIdentifier)
        timeZoneIdentifier = try container.decode(String.self, forKey: .timeZoneIdentifier)
        sessionIdentifier = try container.decodeIfPresent(String.self, forKey: .sessionIdentifier)
            ?? StockChartSeriesCacheStore.defaultSessionIdentifier
        isComplete = try container.decode(Bool.self, forKey: .isComplete)
        candles = try container.decode([IntradayCandle].self, forKey: .candles)
    }
}

struct DailyCloseCacheEntry: Codable, Equatable {
    let timestamp: Date
    let closePrice: Decimal
}

final class StockChartSeriesCacheStore {
    private enum Key {
        static let intradaySeriesCache = "intradaySeriesCache"
        static let dailyCloseCache = "dailyCloseCache"
    }

    private static let suiteName = "com.tasokiii.ScreenStocker.marketDataCache"
    static let defaultSessionIdentifier = "default"

    private let defaults: UserDefaults
    private let mirrorsSharedCache: Bool
    private let lock = NSRecursiveLock()
    private var cachedEntries: [String: IntradaySeriesCacheEntry]?
    private var cachedDailyCloseEntries: [String: [DailyCloseCacheEntry]]?

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: StockChartSeriesCacheStore.suiteName) ?? .standard
        self.mirrorsSharedCache = defaults == nil
        pruneStaleEntries()
    }

    func marketCalendar(country: String) -> StockMarketCalendarCache? {
        lock.lock()
        defer { lock.unlock() }
        let key = "marketCalendar.\(country)"
        var sources = [defaults.data(forKey: key)]
        if mirrorsSharedCache {
            sources += Self.sharedCacheURLs().map { Self.readPreferenceFile(at: $0)?[key] as? Data }
        }
        return sources.compactMap { data in
            data.flatMap { try? PropertyListDecoder().decode(StockMarketCalendarCache.self, from: $0) }
        }.max { $0.fetchedAt < $1.fetchedAt }
    }

    func saveMarketCalendar(
        _ calendar: StockMarketCalendar,
        country: String,
        queryDay: String,
        fetchedAt: Date
    ) {
        lock.lock()
        defer { lock.unlock() }
        var days = Dictionary((marketCalendar(country: country)?.days ?? []).map { ($0.date, $0) },
                              uniquingKeysWith: { _, new in new })
        for day in calendar.days { days[day.date] = day }
        let retainedDays = days.values.filter {
            Self.daysBetween($0.date, and: queryDay).map { $0 <= 14 } ?? false
        }.sorted { $0.date < $1.date }
        let cache = StockMarketCalendarCache(queryDay: queryDay, fetchedAt: fetchedAt, days: retainedDays)
        guard let data = try? PropertyListEncoder().encode(cache) else { return }
        let key = "marketCalendar.\(country)"
        defaults.set(data, forKey: key)
        defaults.synchronize()
        guard mirrorsSharedCache else { return }
        for url in Self.sharedCacheURLs() {
            Self.updatePreferenceFile(at: url) { $0[key] = data }
        }
    }

    func entry(
        for symbol: String,
        dayIdentifier: String,
        timeZoneIdentifier: String,
        sessionIdentifier: String = StockChartSeriesCacheStore.defaultSessionIdentifier,
        referenceDate: Date = Date()
    ) -> IntradaySeriesCacheEntry? {
        lock.lock()
        defer { lock.unlock() }

        pruneStaleEntries(referenceDate: referenceDate)
        guard let entries = loadEntries() else {
            return nil
        }

        let key = Self.cacheKey(
            symbol: symbol,
            dayIdentifier: dayIdentifier,
            timeZoneIdentifier: timeZoneIdentifier,
            sessionIdentifier: sessionIdentifier
        )
        if let entry = entries[key] {
            return entry
        }

        return entries.values.first {
            $0.symbol == symbol
                && $0.dayIdentifier == dayIdentifier
                && $0.timeZoneIdentifier == timeZoneIdentifier
                && $0.sessionIdentifier == sessionIdentifier
        }
    }

    func latestEntry(
        for symbol: String,
        timeZoneIdentifier: String,
        sessionIdentifier: String = StockChartSeriesCacheStore.defaultSessionIdentifier
    ) -> IntradaySeriesCacheEntry? {
        lock.lock()
        defer { lock.unlock() }

        return loadEntries()?.values
            .filter {
                $0.symbol == symbol
                    && $0.timeZoneIdentifier == timeZoneIdentifier
                    && $0.sessionIdentifier == sessionIdentifier
                    && !$0.candles.isEmpty
            }
            .max { lhs, rhs in
                (lhs.candles.map(\.timestamp).max() ?? .distantPast)
                    < (rhs.candles.map(\.timestamp).max() ?? .distantPast)
            }
    }

    func entries(
        for symbol: String,
        timeZoneIdentifier: String,
        sessionIdentifier: String = StockChartSeriesCacheStore.defaultSessionIdentifier
    ) -> [IntradaySeriesCacheEntry] {
        lock.lock()
        defer { lock.unlock() }

        return loadEntries()?.values
            .filter {
                $0.symbol == symbol
                    && $0.timeZoneIdentifier == timeZoneIdentifier
                    && $0.sessionIdentifier == sessionIdentifier
                    && !$0.candles.isEmpty
            }
            .sorted {
                Self.latestTimestamp(in: $0) > Self.latestTimestamp(in: $1)
            } ?? []
    }

    func preferredEntry(
        for symbol: String,
        timeZoneIdentifier: String,
        sessionIdentifier: String = StockChartSeriesCacheStore.defaultSessionIdentifier,
        referenceDate: Date = Date()
    ) -> IntradaySeriesCacheEntry? {
        lock.lock()
        defer { lock.unlock() }

        pruneStaleEntries(referenceDate: referenceDate)
        return latestEntry(for: symbol, timeZoneIdentifier: timeZoneIdentifier, sessionIdentifier: sessionIdentifier)
    }

    func save(
        candles: [IntradayCandle],
        isComplete: Bool,
        for symbol: String,
        dayIdentifier: String,
        timeZoneIdentifier: String,
        sessionIdentifier: String = StockChartSeriesCacheStore.defaultSessionIdentifier,
        referenceDate: Date = Date()
    ) {
        lock.lock()
        defer { lock.unlock() }

        pruneStaleEntries(referenceDate: referenceDate)
        var entries = loadEntries() ?? [:]
        let key = Self.cacheKey(
            symbol: symbol,
            dayIdentifier: dayIdentifier,
            timeZoneIdentifier: timeZoneIdentifier,
            sessionIdentifier: sessionIdentifier
        )
        entries[key] = IntradaySeriesCacheEntry(
            symbol: symbol,
            dayIdentifier: dayIdentifier,
            timeZoneIdentifier: timeZoneIdentifier,
            sessionIdentifier: sessionIdentifier,
            isComplete: isComplete,
            candles: candles.sorted(by: { $0.timestamp < $1.timestamp })
        )
        store(entries: entries)
    }

    func dailyCloses(for symbol: String) -> [DailyCloseCacheEntry] {
        lock.lock()
        defer { lock.unlock() }

        return loadDailyCloseEntries()?[symbol] ?? []
    }

    func saveDailyCloses(_ closes: [DailyCloseCacheEntry], for symbol: String) {
        lock.lock()
        defer { lock.unlock() }

        guard !closes.isEmpty else { return }

        var entries = loadDailyCloseEntries() ?? [:]
        var closesByTimestamp = Dictionary(
            uniqueKeysWithValues: (entries[symbol] ?? []).map { ($0.timestamp, $0) }
        )
        for close in closes {
            closesByTimestamp[close.timestamp] = close
        }
        entries[symbol] = Array(
            closesByTimestamp.values
                .sorted { $0.timestamp > $1.timestamp }
                .prefix(10)
        )
        storeDailyCloseEntries(entries)
    }

    func pruneStaleEntries(referenceDate: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }

        guard var entries = loadEntries() else { return }

        let filteredEntries = entries.filter { _, entry in
            Self.isEntryRecent(entry, referenceDate: referenceDate)
        }

        guard filteredEntries.count != entries.count else { return }
        entries = filteredEntries
        store(entries: entries)
    }

    private static func isEntryRecent(_ entry: IntradaySeriesCacheEntry, referenceDate: Date) -> Bool {
        guard let timeZone = TimeZone(identifier: entry.timeZoneIdentifier) else {
            return false
        }

        let referenceDay = dayIdentifier(for: referenceDate, timeZone: timeZone)
        return daysBetween(entry.dayIdentifier, and: referenceDay).map { $0 <= 14 } ?? false
    }

    private static func daysBetween(_ lhs: String, and rhs: String) -> Int? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        guard let lhsDate = formatter.date(from: lhs),
              let rhsDate = formatter.date(from: rhs) else {
            return nil
        }

        return Calendar(identifier: .gregorian)
            .dateComponents([.day], from: lhsDate, to: rhsDate)
            .day
            .map(abs)
    }

    private func loadEntries() -> [String: IntradaySeriesCacheEntry]? {
        if let cachedEntries {
            return cachedEntries.isEmpty ? nil : cachedEntries
        }

        var mergedEntries: [String: IntradaySeriesCacheEntry] = [:]

        for entries in cacheEntrySources() {
            mergedEntries = Self.mergedEntries(mergedEntries, entries)
        }

        cachedEntries = mergedEntries
        return mergedEntries.isEmpty ? nil : mergedEntries
    }

    private func store(entries: [String: IntradaySeriesCacheEntry]) {
        guard let data = try? PropertyListEncoder().encode(entries) else {
            return
        }
        cachedEntries = entries
        defaults.set(data, forKey: Key.intradaySeriesCache)
        defaults.synchronize()

        guard mirrorsSharedCache else { return }
        for url in Self.sharedCacheURLs() {
            Self.updateCacheFile(at: url, data: data)
        }
    }

    private func loadDailyCloseEntries() -> [String: [DailyCloseCacheEntry]]? {
        if let cachedDailyCloseEntries {
            return cachedDailyCloseEntries.isEmpty ? nil : cachedDailyCloseEntries
        }

        var mergedEntries: [String: [DailyCloseCacheEntry]] = [:]

        for entries in dailyCloseEntrySources() {
            for (symbol, closes) in entries {
                var closesByTimestamp = Dictionary(
                    uniqueKeysWithValues: (mergedEntries[symbol] ?? []).map { ($0.timestamp, $0) }
                )
                for close in closes {
                    closesByTimestamp[close.timestamp] = close
                }
                mergedEntries[symbol] = Array(
                    closesByTimestamp.values
                        .sorted { $0.timestamp > $1.timestamp }
                        .prefix(10)
                )
            }
        }

        cachedDailyCloseEntries = mergedEntries
        return mergedEntries.isEmpty ? nil : mergedEntries
    }

    private func storeDailyCloseEntries(_ entries: [String: [DailyCloseCacheEntry]]) {
        guard let data = try? PropertyListEncoder().encode(entries) else {
            return
        }
        cachedDailyCloseEntries = entries
        defaults.set(data, forKey: Key.dailyCloseCache)
        defaults.synchronize()

        guard mirrorsSharedCache else { return }
        for url in Self.sharedCacheURLs() {
            Self.updateDailyCloseCacheFile(at: url, data: data)
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

    private func dailyCloseEntrySources() -> [[String: [DailyCloseCacheEntry]]] {
        var sources: [[String: [DailyCloseCacheEntry]]] = []

        if let data = defaults.data(forKey: Key.dailyCloseCache),
           let entries = Self.decodeDailyCloseEntries(from: data) {
            sources.append(entries)
        }

        guard mirrorsSharedCache else { return sources }
        for url in Self.sharedCacheURLs() {
            guard let entries = Self.readDailyCloseCacheFile(at: url) else {
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
        for (key, newEntry) in newEntries {
            let normalizedKey = normalizedEntryKey(key, entry: newEntry)
            guard let existingEntry = mergedEntries[normalizedKey] else {
                mergedEntries[normalizedKey] = newEntry
                continue
            }

            guard existingEntry.dayIdentifier == newEntry.dayIdentifier,
                  existingEntry.timeZoneIdentifier == newEntry.timeZoneIdentifier,
                  existingEntry.sessionIdentifier == newEntry.sessionIdentifier else {
                mergedEntries[normalizedKey] = newerEntry(existingEntry, newEntry)
                continue
            }

            var candlesByTimestamp: [Date: IntradayCandle] = [:]
            for candle in existingEntry.candles {
                candlesByTimestamp[candle.timestamp] = candle
            }
            for candle in newEntry.candles {
                candlesByTimestamp[candle.timestamp] = candle
            }

            mergedEntries[normalizedKey] = IntradaySeriesCacheEntry(
                symbol: existingEntry.symbol,
                dayIdentifier: existingEntry.dayIdentifier,
                timeZoneIdentifier: existingEntry.timeZoneIdentifier,
                sessionIdentifier: existingEntry.sessionIdentifier,
                isComplete: existingEntry.isComplete || newEntry.isComplete,
                candles: candlesByTimestamp.values.sorted { $0.timestamp < $1.timestamp }
            )
        }
        return mergedEntries
    }

    private static func normalizedEntryKey(_ key: String, entry: IntradaySeriesCacheEntry) -> String {
        if key.contains("|") {
            return key
        }
        return cacheKey(
            symbol: entry.symbol,
            dayIdentifier: entry.dayIdentifier,
            timeZoneIdentifier: entry.timeZoneIdentifier,
            sessionIdentifier: entry.sessionIdentifier
        )
    }

    private static func cacheKey(
        symbol: String,
        dayIdentifier: String,
        timeZoneIdentifier: String,
        sessionIdentifier: String
    ) -> String {
        "\(symbol)|\(timeZoneIdentifier)|\(sessionIdentifier)|\(dayIdentifier)"
    }

    private static func newerEntry(
        _ lhs: IntradaySeriesCacheEntry,
        _ rhs: IntradaySeriesCacheEntry
    ) -> IntradaySeriesCacheEntry {
        let lhsTimestamp = latestTimestamp(in: lhs)
        let rhsTimestamp = latestTimestamp(in: rhs)
        return rhsTimestamp >= lhsTimestamp ? rhs : lhs
    }

    private static func latestTimestamp(in entry: IntradaySeriesCacheEntry) -> Date {
        entry.candles.map(\.timestamp).max() ?? .distantPast
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

    private static func decodeDailyCloseEntries(from data: Data) -> [String: [DailyCloseCacheEntry]]? {
        try? PropertyListDecoder().decode([String: [DailyCloseCacheEntry]].self, from: data)
    }

    private static func readDailyCloseCacheFile(at url: URL) -> [String: [DailyCloseCacheEntry]]? {
        guard let preferences = readPreferenceFile(at: url),
              let data = preferences[Key.dailyCloseCache] as? Data else {
            return nil
        }
        return decodeDailyCloseEntries(from: data)
    }

    private static func updateCacheFile(at url: URL, data: Data) {
        updatePreferenceFile(at: url) { preferences in
            preferences[Key.intradaySeriesCache] = data
        }
    }

    private static func updateDailyCloseCacheFile(at url: URL, data: Data) {
        updatePreferenceFile(at: url) { preferences in
            preferences[Key.dailyCloseCache] = data
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

}
