import Foundation
import ScreenSaver

final class StockerPreferences {
    private let defaults = ScreenSaverDefaults(forModuleWithName: "ScreenStocker")

    var symbols: [String] {
        get {
            let stored = defaults?.string(forKey: "symbols") ?? "AAPL,MSFT,NVDA,TSLA"
            return stored
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                .filter { !$0.isEmpty }
        }
        set {
            defaults?.set(newValue.joined(separator: ","), forKey: "symbols")
            defaults?.synchronize()
        }
    }
}

