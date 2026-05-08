import Foundation
import ScreenSaver
import Security

final class StockerPreferences {
    static let didChangeNotification = Notification.Name("com.lukeoh.ScreenStocker.preferencesChanged")

    private enum Key {
        static let registeredSymbols = "registeredSymbols"
        static let legacySymbols = "symbols"
        static let selectedSymbol = "selectedSymbol"
    }

    private static let suiteName = "com.lukeoh.ScreenStocker.preferences"

    private let defaults: UserDefaults
    private let legacyDefaults = ScreenSaverDefaults(forModuleWithName: "ScreenStocker")
    private let credentialStore = KoreaInvestmentCredentialStore()

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
        symbols.first ?? "005930"
    }

    var registeredSymbols: [String] {
        get {
            syncDefaults()
            let stored = defaults.string(forKey: Key.registeredSymbols)
                ?? defaults.string(forKey: Key.legacySymbols)
            ?? "005930,000660,035420,005380"
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

    var koreaInvestmentAppKey: String {
        get {
            credentialStore.read(account: .appKey)
        }
        set {
            credentialStore.save(newValue, account: .appKey)
            syncDefaults()
            notifyChanged()
        }
    }

    var koreaInvestmentAppSecret: String {
        get {
            credentialStore.read(account: .appSecret)
        }
        set {
            credentialStore.save(newValue, account: .appSecret)
            syncDefaults()
            notifyChanged()
        }
    }

    var koreaInvestmentCredentials: KoreaInvestmentCredentials {
        KoreaInvestmentCredentials(appKey: koreaInvestmentAppKey, appSecret: koreaInvestmentAppSecret)
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

    private final class KoreaInvestmentCredentialStore {
        enum Account: String {
            case appKey
            case appSecret
        }

        private let service = "com.lukeoh.ScreenStocker.koreainvestment"

        func read(account: Account) -> String {
            var query = baseQuery(account: account)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess,
                  let data = item as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                return ""
            }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func save(_ value: String, account: Account) {
            let credential = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !credential.isEmpty else {
                SecItemDelete(baseQuery(account: account) as CFDictionary)
                return
            }

            let data = Data(credential.utf8)
            let attributes = [kSecValueData as String: data]
            let status = SecItemUpdate(baseQuery(account: account) as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                var item = baseQuery(account: account)
                item[kSecValueData as String] = data
                SecItemAdd(item as CFDictionary, nil)
            }
        }

        private func baseQuery(account: Account) -> [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account.rawValue
            ]
        }
    }
}
