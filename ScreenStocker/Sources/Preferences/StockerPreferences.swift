import Foundation
import ScreenSaver

final class StockerPreferences {
    static let didChangeNotification = Notification.Name("com.lukeoh.ScreenStocker.preferencesChanged")

    private enum Key {
        static let registeredSymbols = "registeredSymbols"
        static let legacySymbols = "symbols"
        static let selectedSymbol = "selectedSymbol"
        static let twelveDataAPIKey = "twelveDataAPIKey"
    }

    private static let suiteName = "com.lukeoh.ScreenStocker.preferences"

    private let defaults: UserDefaults
    private let legacyDefaults = ScreenSaverDefaults(forModuleWithName: "ScreenStocker")

    init(defaults: UserDefaults? = UserDefaults(suiteName: StockerPreferences.suiteName)) {
        self.defaults = defaults ?? .standard
        migrateLegacyDefaultsIfNeeded()
    }

    var symbols: [String] {
        get {
            if let selectedSymbol {
                return [selectedSymbol]
            }
            return registeredSymbols
        }
        set {
            registeredSymbols = newValue
        }
    }

    var primarySymbol: String {
        symbols.first ?? "AAPL"
    }

    var registeredSymbols: [String] {
        get {
            syncDefaults()
            let stored = defaults.string(forKey: Key.registeredSymbols)
                ?? defaults.string(forKey: Key.legacySymbols)
                ?? "AAPL,MSFT,NVDA,TSLA"
            return normalize(symbols: stored.split(separator: ",").map(String.init))
        }
        set {
            defaults.set(normalize(symbols: newValue).joined(separator: ","), forKey: Key.registeredSymbols)
            syncDefaults()
            notifyChanged()
        }
    }

    var selectedSymbol: String? {
        get {
            syncDefaults()
            guard let stored = defaults.string(forKey: Key.selectedSymbol), !stored.isEmpty else {
                return nil
            }
            return stored
        }
        set {
            defaults.set(newValue ?? "", forKey: Key.selectedSymbol)
            syncDefaults()
            notifyChanged()
        }
    }

    var twelveDataAPIKey: String {
        get {
            syncDefaults()
            return defaults.string(forKey: Key.twelveDataAPIKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.twelveDataAPIKey)
            syncDefaults()
            notifyChanged()
        }
    }

    private func migrateLegacyDefaultsIfNeeded() {
        syncDefaults()

        if defaults.object(forKey: Key.registeredSymbols) == nil {
            let legacySymbols = legacyDefaults?.string(forKey: Key.registeredSymbols)
                ?? legacyDefaults?.string(forKey: Key.legacySymbols)
            if let legacySymbols {
                defaults.set(legacySymbols, forKey: Key.registeredSymbols)
            }
        }

        if defaults.object(forKey: Key.selectedSymbol) == nil,
           let legacySelectedSymbol = legacyDefaults?.string(forKey: Key.selectedSymbol) {
            defaults.set(legacySelectedSymbol, forKey: Key.selectedSymbol)
        }

        if defaults.object(forKey: Key.twelveDataAPIKey) == nil,
           let legacyAPIKey = legacyDefaults?.string(forKey: Key.twelveDataAPIKey) {
            defaults.set(legacyAPIKey, forKey: Key.twelveDataAPIKey)
        }

        syncDefaults()
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
            guard !normalized.isEmpty, !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return normalized
        }
    }
}
