import Foundation
import ScreenSaver
import Security
import Darwin

final class StockerPreferences {
    static let didChangeNotification = Notification.Name("com.lukeoh.ScreenStocker.preferencesChanged")
    static let fallbackSymbol = "005930"
    static let demoSymbols = ["005930", "000660", "035420", "005380"]

    private enum Key {
        static let registeredSymbols = "registeredSymbols"
        static let legacySymbols = "symbols"
        static let selectedSymbol = "selectedSymbol"
        static let watchlistSaved = "watchlistSaved"
    }

    private static let suiteName = "com.lukeoh.ScreenStocker.preferences"
    private static let legacyModuleName = "ScreenStocker"
    private static let invalidSymbols: Set<String> = ["KOSDAQ", "KOSPI", "KONEX"]

    private let defaults: UserDefaults
    private let legacyDefaults = ScreenSaverDefaults(forModuleWithName: StockerPreferences.legacyModuleName)
    private let credentialStore = KoreaInvestmentCredentialStore()

    init(defaults: UserDefaults? = UserDefaults(suiteName: StockerPreferences.suiteName)) {
        self.defaults = defaults ?? .standard
        migrateLegacyDefaultsIfNeeded()
        repairStoredValuesIfNeeded()
        mirrorSharedPreferences()
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

    var symbolForScreenSaverDisplay: String? {
        if let selectedSymbol {
            return selectedSymbol
        }
        return registeredSymbols.first
    }

    var registeredSymbols: [String] {
        get {
            syncDefaults()
            guard let stored = Self.hostPreferenceString(forKey: Key.registeredSymbols)
                ?? Self.hostPreferenceString(forKey: Key.legacySymbols)
                ?? defaults.string(forKey: Key.registeredSymbols)
                ?? defaults.string(forKey: Key.legacySymbols) else {
                return []
            }
            let symbols = normalize(symbols: stored.split(separator: ",").map(String.init))
            if defaults.object(forKey: Key.watchlistSaved) == nil, symbols == Self.demoSymbols {
                return []
            }
            return symbols
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

    var koreaInvestmentAppKey: String {
        get {
            credentialStore.read(account: .appKey)
        }
        set {
            try? saveKoreaInvestmentCredentials(appKey: newValue, appSecret: koreaInvestmentAppSecret)
        }
    }

    var koreaInvestmentAppSecret: String {
        get {
            credentialStore.read(account: .appSecret)
        }
        set {
            try? saveKoreaInvestmentCredentials(appKey: koreaInvestmentAppKey, appSecret: newValue)
        }
    }

    var koreaInvestmentCredentials: KoreaInvestmentCredentials {
        KoreaInvestmentCredentials(appKey: koreaInvestmentAppKey, appSecret: koreaInvestmentAppSecret)
    }

    func saveKoreaInvestmentCredentials(appKey: String, appSecret: String) throws {
        let credentials = KoreaInvestmentCredentials(appKey: appKey, appSecret: appSecret)
        try credentialStore.save(credentials.appKey, account: .appKey)
        try credentialStore.save(credentials.appSecret, account: .appSecret)

        let storedCredentials = koreaInvestmentCredentials
        guard storedCredentials == credentials else {
            throw CredentialStoreError.verificationFailed
        }

        syncDefaults()
        notifyChanged()
    }

    private func migrateLegacyDefaultsIfNeeded() {
        syncDefaults()

        if defaults.object(forKey: Key.registeredSymbols) == nil {
            let legacySymbols = legacyDefaults?.string(forKey: Key.registeredSymbols)
                ?? legacyDefaults?.string(forKey: Key.legacySymbols)
            let migratedSymbols = normalize(symbols: legacySymbols?.split(separator: ",").map(String.init) ?? [])
            if !migratedSymbols.isEmpty {
                defaults.set(migratedSymbols.joined(separator: ","), forKey: Key.registeredSymbols)
                defaults.set(true, forKey: Key.watchlistSaved)
            }
        }

        if defaults.object(forKey: Key.selectedSymbol) == nil,
           let legacySelectedSymbol = normalize(symbols: [legacyDefaults?.string(forKey: Key.selectedSymbol) ?? ""]).first {
            defaults.set(legacySelectedSymbol, forKey: Key.selectedSymbol)
        }

        syncDefaults()
    }

    private func repairStoredValuesIfNeeded() {
        let symbols = registeredSymbols
        let repairedSymbols = symbols.joined(separator: ",")
        var didRepair = false

        if let storedSymbols = defaults.string(forKey: Key.registeredSymbols),
           storedSymbols != repairedSymbols {
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
        let joinedSymbols = symbols.joined(separator: ",")

        legacyDefaults?.set(joinedSymbols, forKey: Key.registeredSymbols)
        legacyDefaults?.set(joinedSymbols, forKey: Key.legacySymbols)
        legacyDefaults?.set(selectedSymbol, forKey: Key.selectedSymbol)
        legacyDefaults?.synchronize()

        for url in Self.screenSaverPreferenceURLs() {
            Self.updatePreferenceFile(at: url) { preferences in
                preferences[Key.registeredSymbols] = joinedSymbols
                preferences[Key.legacySymbols] = joinedSymbols
                preferences[Key.selectedSymbol] = selectedSymbol
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

        func save(_ value: String, account: Account) throws {
            let credential = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !credential.isEmpty else {
                let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
                guard status == errSecSuccess || status == errSecItemNotFound else {
                    throw CredentialStoreError.keychainStatus(status)
                }
                return
            }

            let data = Data(credential.utf8)
            let attributes = [kSecValueData as String: data]
            let status = SecItemUpdate(baseQuery(account: account) as CFDictionary, attributes as CFDictionary)
            switch status {
            case errSecSuccess:
                return
            case errSecItemNotFound:
                var item = baseQuery(account: account)
                item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
                let addStatus = SecItemAdd(item as CFDictionary, nil)
                guard addStatus == errSecSuccess else {
                    throw CredentialStoreError.keychainStatus(addStatus)
                }
            default:
                throw CredentialStoreError.keychainStatus(status)
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

private enum CredentialStoreError: LocalizedError {
    case keychainStatus(OSStatus)
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .keychainStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain error \(status): \(message)"
            }
            return "Keychain error \(status)"
        case .verificationFailed:
            return "Saved credentials could not be verified in Keychain."
        }
    }
}
