import Foundation

#if canImport(Security)
import Security

struct KeychainStore<Value: Codable>: Sendable {
    let service: String

    init(service: String) {
        self.service = service
    }

    func load(account: String) async throws -> Value? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainStoreError.status(status)
        }
        guard let data = item as? Data else {
            throw KeychainStoreError.invalidData
        }
        return try JSONDecoder().decode(Value.self, from: data)
    }

    func save(account: String, value: Value) async throws {
        let data = try JSONEncoder().encode(value)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainStoreError.status(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainStoreError.status(status)
        }
    }

    func delete(account: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.status(status)
        }
    }
}

enum KeychainStoreError: Error, Sendable {
    case status(OSStatus)
    case invalidData
}
#endif
