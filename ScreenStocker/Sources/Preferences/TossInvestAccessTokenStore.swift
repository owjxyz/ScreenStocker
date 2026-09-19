import Foundation
import Security

struct TossInvestAccessToken: Codable, Equatable {
    let value: String
    let expiresAt: Date
}

protocol TossInvestAccessTokenStoring: AnyObject {
    func token(for credentials: TossInvestCredentials, now: Date) -> TossInvestAccessToken?
    func save(_ token: TossInvestAccessToken, for credentials: TossInvestCredentials)
    func invalidate(_ token: String, for credentials: TossInvestCredentials)
}

final class TossInvestAccessTokenStore: TossInvestAccessTokenStoring {
    private struct Entry: Codable { let credentials: TossInvestCredentials; let token: TossInvestAccessToken }
    private let service = "com.tasokiii.ScreenStocker.tossinvest-open-api"
    private let account = "accessToken"

    func token(for credentials: TossInvestCredentials, now: Date) -> TossInvestAccessToken? {
        guard let data = read(), let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.credentials == credentials, entry.token.expiresAt > now else { return nil }
        return entry.token
    }

    func save(_ token: TossInvestAccessToken, for credentials: TossInvestCredentials) {
        guard let data = try? JSONEncoder().encode(Entry(credentials: credentials, token: token)) else { return }
        let query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var add = query; attributes.forEach { add[$0.key] = $0.value }; _ = SecItemAdd(add as CFDictionary, nil)
        }
    }

    func invalidate(_ token: String, for credentials: TossInvestCredentials) {
        guard let data = read(), let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.credentials == credentials, entry.token.value == token else { return }
        _ = SecItemDelete(baseQuery() as CFDictionary)
    }

    private func read() -> Data? {
        var query = baseQuery(); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?; guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func baseQuery() -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }
}
