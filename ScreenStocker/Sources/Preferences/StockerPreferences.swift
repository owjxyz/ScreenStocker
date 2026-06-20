import Foundation
import ScreenSaver
import Darwin

enum ScreenSaverAppearanceMode: String, CaseIterable {
    case light
    case dark
    case automatic

    var title: String {
        switch self {
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        case .automatic:
            return "Auto"
        }
    }

    var systemImage: String {
        switch self {
        case .light:
            return "sun.max"
        case .dark:
            return "moon"
        case .automatic:
            return "circle.lefthalf.filled"
        }
    }

    var next: ScreenSaverAppearanceMode {
        switch self {
        case .light:
            return .dark
        case .dark:
            return .automatic
        case .automatic:
            return .light
        }
    }
}

enum ScreenSaverChartStyle: String, CaseIterable {
    case line
    case candlestick

    var title: String {
        switch self {
        case .line:
            return "Line Chart"
        case .candlestick:
            return "Candlestick Chart"
        }
    }

    var systemImage: String {
        switch self {
        case .line:
            return "chart.xyaxis.line"
        case .candlestick:
            return "chart.bar"
        }
    }
}

final class StockerPreferences {
    static let didChangeNotification = Notification.Name("com.lukeoh.ScreenStocker.preferencesChanged")
    static let defaultSymbols = MarketDataCatalog.symbols

    private enum Key {
        static let registeredSymbols = "registeredSymbols"
        static let legacySymbols = "symbols"
        static let selectedSymbol = "selectedSymbol"
        static let appearanceMode = "appearanceMode"
        static let chartStyle = "chartStyle"
        static let watchlistSaved = "watchlistSaved"
    }

    private static let suiteName = "com.lukeoh.ScreenStocker.preferences"
    private static let legacyModuleName = "ScreenStocker"
    private static let invalidSymbols: Set<String> = ["KOSDAQ", "KOSPI", "KONEX"]

    private let defaults: UserDefaults
    private let legacyDefaults = ScreenSaverDefaults(forModuleWithName: StockerPreferences.legacyModuleName)

    init(defaults: UserDefaults? = UserDefaults(suiteName: StockerPreferences.suiteName)) {
        self.defaults = defaults ?? .standard
        migrateLegacyDefaultsIfNeeded()
        repairStoredValuesIfNeeded()
        mirrorSharedPreferences()
    }

    var symbolForScreenSaverDisplay: String? {
        selectedSymbol ?? registeredSymbols.first ?? Self.defaultSymbols.first
    }

    var registeredSymbols: [String] {
        get {
            syncDefaults()
            guard let stored = Self.hostPreferenceString(forKey: Key.registeredSymbols)
                ?? Self.hostPreferenceString(forKey: Key.legacySymbols)
                ?? defaults.string(forKey: Key.registeredSymbols)
                ?? defaults.string(forKey: Key.legacySymbols) else {
                return Self.defaultSymbols
            }
            let symbols = normalize(symbols: stored.split(separator: ",").map(String.init))
            return symbols.isEmpty ? Self.defaultSymbols : symbols
        }
        set {
            defaults.set(normalize(symbols: newValue).joined(separator: ","), forKey: Key.registeredSymbols)
            defaults.set(true, forKey: Key.watchlistSaved)
            syncDefaults()
            mirrorSharedPreferences()
            notifyChanged()
        }
    }

    var selectedSymbol: String? {
        get {
            syncDefaults()
            let storedSymbols = [
                defaults.string(forKey: Key.selectedSymbol),
                Self.hostPreferenceString(forKey: Key.selectedSymbol)
            ].compactMap { $0 }

            for stored in storedSymbols where !stored.isEmpty {
                if let selected = normalize(symbols: [stored]).first,
                   registeredSymbols.contains(selected) {
                    return selected
                }
            }
            return nil
        }
        set {
            let selected = normalize(symbols: [newValue ?? ""]).first
            defaults.set(selected ?? "", forKey: Key.selectedSymbol)
            syncDefaults()
            mirrorSharedPreferences()
            notifyChanged()
        }
    }

    var appearanceMode: ScreenSaverAppearanceMode {
        get {
            syncDefaults()
            let storedMode = defaults.string(forKey: Key.appearanceMode)
                ?? Self.hostPreferenceString(forKey: Key.appearanceMode)
            return storedMode.flatMap(ScreenSaverAppearanceMode.init(rawValue:)) ?? .dark
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.appearanceMode)
            syncDefaults()
            mirrorSharedPreferences()
            notifyChanged()
        }
    }

    var chartStyle: ScreenSaverChartStyle {
        get {
            syncDefaults()
            let storedStyle = defaults.string(forKey: Key.chartStyle)
                ?? Self.hostPreferenceString(forKey: Key.chartStyle)
            return storedStyle.flatMap(ScreenSaverChartStyle.init(rawValue:)) ?? .line
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.chartStyle)
            syncDefaults()
            mirrorSharedPreferences()
            notifyChanged()
        }
    }

    private func migrateLegacyDefaultsIfNeeded() {
        syncDefaults()

        if defaults.object(forKey: Key.registeredSymbols) == nil {
            let legacySymbols = legacyDefaults?.string(forKey: Key.registeredSymbols)
                ?? legacyDefaults?.string(forKey: Key.legacySymbols)
            let migratedSymbols = normalize(symbols: legacySymbols?.split(separator: ",").map(String.init) ?? [])
            defaults.set((migratedSymbols.isEmpty ? Self.defaultSymbols : migratedSymbols).joined(separator: ","), forKey: Key.registeredSymbols)
            defaults.set(true, forKey: Key.watchlistSaved)
        }

        if defaults.object(forKey: Key.selectedSymbol) == nil,
           let legacySelectedSymbol = normalize(symbols: [legacyDefaults?.string(forKey: Key.selectedSymbol) ?? ""]).first {
            defaults.set(legacySelectedSymbol, forKey: Key.selectedSymbol)
        }

        if defaults.object(forKey: Key.appearanceMode) == nil,
           let legacyMode = legacyDefaults?.string(forKey: Key.appearanceMode),
           ScreenSaverAppearanceMode(rawValue: legacyMode) != nil {
            defaults.set(legacyMode, forKey: Key.appearanceMode)
        }

        if defaults.object(forKey: Key.chartStyle) == nil,
           let legacyStyle = legacyDefaults?.string(forKey: Key.chartStyle),
           ScreenSaverChartStyle(rawValue: legacyStyle) != nil {
            defaults.set(legacyStyle, forKey: Key.chartStyle)
        }

        syncDefaults()
    }

    private func repairStoredValuesIfNeeded() {
        let symbols = registeredSymbols
        let repairedSymbols = symbols.joined(separator: ",")
        var didRepair = false

        if defaults.string(forKey: Key.registeredSymbols) != repairedSymbols {
            defaults.set(repairedSymbols, forKey: Key.registeredSymbols)
            didRepair = true
        }

        if let storedSelectedSymbol = defaults.string(forKey: Key.selectedSymbol), !storedSelectedSymbol.isEmpty {
            let selectedSymbol = normalize(symbols: [storedSelectedSymbol]).first
            if selectedSymbol == nil || !symbols.contains(selectedSymbol!) {
                defaults.set("", forKey: Key.selectedSymbol)
                didRepair = true
            }
        }

        if let storedAppearanceMode = defaults.string(forKey: Key.appearanceMode),
           ScreenSaverAppearanceMode(rawValue: storedAppearanceMode) == nil {
            defaults.set(ScreenSaverAppearanceMode.dark.rawValue, forKey: Key.appearanceMode)
            didRepair = true
        }

        if let storedChartStyle = defaults.string(forKey: Key.chartStyle),
           ScreenSaverChartStyle(rawValue: storedChartStyle) == nil {
            defaults.set(ScreenSaverChartStyle.line.rawValue, forKey: Key.chartStyle)
            didRepair = true
        }

        if didRepair {
            syncDefaults()
            mirrorSharedPreferences()
        }
    }

    private func syncDefaults() {
        defaults.synchronize()
    }

    private func notifyChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            Self.didChangeNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func normalize(symbols: [String]) -> [String] {
        var seen = Set<String>()
        return symbols.compactMap { symbol in
            let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !normalized.isEmpty,
                  !Self.invalidSymbols.contains(normalized),
                  !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return normalized
        }
    }

    private func mirrorSharedPreferences() {
        let symbols = registeredSymbols
        let selectedSymbol = self.selectedSymbol ?? ""
        let appearanceMode = self.appearanceMode.rawValue
        let chartStyle = self.chartStyle.rawValue
        let joinedSymbols = symbols.joined(separator: ",")

        legacyDefaults?.set(joinedSymbols, forKey: Key.registeredSymbols)
        legacyDefaults?.set(joinedSymbols, forKey: Key.legacySymbols)
        legacyDefaults?.set(selectedSymbol, forKey: Key.selectedSymbol)
        legacyDefaults?.set(appearanceMode, forKey: Key.appearanceMode)
        legacyDefaults?.set(chartStyle, forKey: Key.chartStyle)
        legacyDefaults?.synchronize()

        for url in Self.screenSaverPreferenceURLs() {
            Self.updatePreferenceFile(at: url) { preferences in
                preferences[Key.registeredSymbols] = joinedSymbols
                preferences[Key.legacySymbols] = joinedSymbols
                preferences[Key.selectedSymbol] = selectedSymbol
                preferences[Key.appearanceMode] = appearanceMode
                preferences[Key.chartStyle] = chartStyle
                preferences[Key.watchlistSaved] = true
            }
        }
    }

    private static func screenSaverPreferenceURLs() -> [URL] {
        let fileManager = FileManager.default
        let home = realHomeDirectory
        let containerPreferences = home
            .appendingPathComponent("Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Preferences", isDirectory: true)

        var urls = [
            containerPreferences.appendingPathComponent("\(suiteName).plist")
        ]

        for byHostDirectory in [
            home.appendingPathComponent("Library/Preferences/ByHost", isDirectory: true),
            containerPreferences.appendingPathComponent("ByHost", isDirectory: true)
        ] {
            let byHostURLs = (try? fileManager.contentsOfDirectory(
                at: byHostDirectory,
                includingPropertiesForKeys: nil
            )) ?? []
            urls.append(contentsOf: byHostURLs.filter { url in
                url.lastPathComponent.hasPrefix("\(legacyModuleName).") && url.pathExtension == "plist"
            })
        }

        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func hostPreferenceString(forKey key: String) -> String? {
        guard let preferences = readPreferenceFile(at: hostPreferenceURL),
              let value = preferences[key] as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static var hostPreferenceURL: URL {
        realHomeDirectory
            .appendingPathComponent("Library/Preferences", isDirectory: true)
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
}
