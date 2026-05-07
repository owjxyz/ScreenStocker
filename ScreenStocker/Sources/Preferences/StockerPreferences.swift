import Foundation
import ScreenSaver

final class StockerPreferences {
    private let defaults = ScreenSaverDefaults(forModuleWithName: "ScreenStocker")

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

    var registeredSymbols: [String] {
        get {
            let stored = defaults?.string(forKey: "registeredSymbols")
                ?? defaults?.string(forKey: "symbols")
                ?? "AAPL,MSFT,NVDA,TSLA"
            return normalize(symbols: stored.split(separator: ",").map(String.init))
        }
        set {
            defaults?.set(normalize(symbols: newValue).joined(separator: ","), forKey: "registeredSymbols")
            defaults?.synchronize()
        }
    }

    var selectedSymbol: String? {
        get {
            guard let stored = defaults?.string(forKey: "selectedSymbol"), !stored.isEmpty else {
                return nil
            }
            return stored
        }
        set {
            defaults?.set(newValue ?? "", forKey: "selectedSymbol")
            defaults?.synchronize()
        }
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
