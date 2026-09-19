import Foundation
import Security
import os

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
    private let logger = Logger(subsystem: "com.tasokiii.ScreenStocker", category: "tokenStore")

    func token(for credentials: TossInvestCredentials, now: Date) -> TossInvestAccessToken? {
        guard let data = read(), let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        guard entry.credentials == credentials, entry.token.expiresAt > now else {
            delete()
            return nil
        }
        return entry.token
    }

    func save(_ token: TossInvestAccessToken, for credentials: TossInvestCredentials) {
        guard let data = try? JSONEncoder().encode(Entry(credentials: credentials, token: token)) else { return }
        let query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var add = query; attributes.forEach { add[$0.key] = $0.value }
            if SecItemAdd(add as CFDictionary, nil) != errSecSuccess { logger.error("Could not save Toss access token.") }
        } else if updateStatus != errSecSuccess {
            logger.error("Could not update Toss access token.")
        }
    }

    func invalidate(_ token: String, for credentials: TossInvestCredentials) {
        guard let data = read(), let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.credentials == credentials, entry.token.value == token else { return }
        delete()
    }

    private func read() -> Data? {
        var query = baseQuery(); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound { logger.error("Could not read Toss access token.") }
            return nil
        }
        return item as? Data
    }

    private func delete() {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound { logger.error("Could not delete Toss access token.") }
    }

    private func baseQuery() -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }
}
