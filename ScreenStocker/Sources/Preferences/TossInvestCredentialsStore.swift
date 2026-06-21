import Foundation
import Security

struct TossInvestCredentials: Equatable {
    var apiKey: String
    var secretKey: String

    var isComplete: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum TossInvestCredentialsStoreError: LocalizedError {
    case missingCredentials
    case invalidEncoding
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Enter both the API key and Secret key."
        case .invalidEncoding:
            return "Could not encode the credentials for Keychain storage."
        case .keychainFailure(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "Keychain returned status \(status)."
        }
    }
}

final class TossInvestCredentialsStore {
    private enum Account {
        static let apiKey = "apiKey"
        static let secretKey = "secretKey"
    }

    private static let serviceName = "com.tasokiii.ScreenStocker.tossinvest-open-api"
    private static let legacyServiceNames = ["com.lukeoh.ScreenStocker.tossinvest-open-api"]

    var credentials: TossInvestCredentials? {
        guard let apiKey = read(account: Account.apiKey, serviceName: Self.serviceName),
              let secretKey = read(account: Account.secretKey, serviceName: Self.serviceName),
              !apiKey.isEmpty,
              !secretKey.isEmpty else {
            return legacyCredentials
        }
        return TossInvestCredentials(apiKey: apiKey, secretKey: secretKey)
    }

    var hasCredentials: Bool {
        credentials?.isComplete == true
    }

    func save(_ credentials: TossInvestCredentials) throws {
        let normalized = TossInvestCredentials(
            apiKey: credentials.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            secretKey: credentials.secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard normalized.isComplete else {
            throw TossInvestCredentialsStoreError.missingCredentials
        }

        try save(normalized.apiKey, account: Account.apiKey)
        try save(normalized.secretKey, account: Account.secretKey)
    }

    func clear() throws {
        try delete(account: Account.apiKey)
        try delete(account: Account.secretKey)
        for serviceName in Self.legacyServiceNames {
            try delete(account: Account.apiKey, serviceName: serviceName)
            try delete(account: Account.secretKey, serviceName: serviceName)
        }
    }

    private var legacyCredentials: TossInvestCredentials? {
        for serviceName in Self.legacyServiceNames {
            guard let apiKey = read(account: Account.apiKey, serviceName: serviceName),
                  let secretKey = read(account: Account.secretKey, serviceName: serviceName),
                  !apiKey.isEmpty,
                  !secretKey.isEmpty else {
                continue
            }

            let credentials = TossInvestCredentials(apiKey: apiKey, secretKey: secretKey)
            try? save(credentials)
            return credentials
        }
        return nil
    }

    private func save(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw TossInvestCredentialsStoreError.invalidEncoding
        }

        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw TossInvestCredentialsStoreError.keychainFailure(updateStatus)
        }

        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw TossInvestCredentialsStoreError.keychainFailure(addStatus)
        }
    }

    private func read(account: String, serviceName: String = TossInvestCredentialsStore.serviceName) -> String? {
        var query = baseQuery(account: account, serviceName: serviceName)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func delete(account: String, serviceName: String = TossInvestCredentialsStore.serviceName) throws {
        let status = SecItemDelete(baseQuery(account: account, serviceName: serviceName) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TossInvestCredentialsStoreError.keychainFailure(status)
        }
    }

    private func baseQuery(account: String, serviceName: String = TossInvestCredentialsStore.serviceName) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
    }
}
