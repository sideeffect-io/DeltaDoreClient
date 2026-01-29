import Foundation

#if canImport(Security)
import Security

public extension TydomGatewayCredentialStore {
    static func liveKeychain(
        service: String = "com.deltadore.tydom.gateway",
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> TydomGatewayCredentialStore {
        TydomGatewayCredentialStore(
            load: { gatewayId in
                try await KeychainStore.load(service: service, account: gatewayId)
            },
            save: { gatewayId, credentials in
                let updated = TydomGatewayCredentials(
                    mac: credentials.mac,
                    password: credentials.password,
                    cachedLocalIP: credentials.cachedLocalIP,
                    updatedAt: now()
                )
                try await KeychainStore.save(service: service, account: gatewayId, credentials: updated)
            },
            delete: { gatewayId in
                try await KeychainStore.delete(service: service, account: gatewayId)
            }
        )
    }
}

private enum KeychainStore {
    private struct Payload: Codable {
        let mac: String
        let password: String
        let cachedLocalIP: String?
        let updatedAt: Date
    }

    static func load(service: String, account: String) async throws -> TydomGatewayCredentials? {
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
            throw KeychainError.status(status)
        }
        guard let data = item as? Data else {
            throw KeychainError.invalidData
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return TydomGatewayCredentials(
            mac: payload.mac,
            password: payload.password,
            cachedLocalIP: payload.cachedLocalIP,
            updatedAt: payload.updatedAt
        )
    }

    static func save(service: String, account: String, credentials: TydomGatewayCredentials) async throws {
        let payload = Payload(
            mac: credentials.mac,
            password: credentials.password,
            cachedLocalIP: credentials.cachedLocalIP,
            updatedAt: credentials.updatedAt
        )
        let data = try JSONEncoder().encode(payload)

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
                throw KeychainError.status(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    static func delete(service: String, account: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    enum KeychainError: Error, Sendable {
        case status(OSStatus)
        case invalidData
    }
}
#endif
