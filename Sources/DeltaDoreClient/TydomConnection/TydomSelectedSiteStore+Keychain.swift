import Foundation

#if canImport(Security)
import Security

public extension TydomSelectedSiteStore {
    static func liveKeychain(
        service: String = "com.deltadore.tydom.selected-site"
    ) -> TydomSelectedSiteStore {
        TydomSelectedSiteStore(
            load: { account in
                try await KeychainStore.load(service: service, account: account)
            },
            save: { account, site in
                try await KeychainStore.save(service: service, account: account, site: site)
            },
            delete: { account in
                try await KeychainStore.delete(service: service, account: account)
            }
        )
    }
}

private enum KeychainStore {
    private struct Payload: Codable {
        let id: String
        let name: String
        let gatewayMac: String
    }

    static func load(service: String, account: String) async throws -> TydomSelectedSite? {
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
        return TydomSelectedSite(id: payload.id, name: payload.name, gatewayMac: payload.gatewayMac)
    }

    static func save(service: String, account: String, site: TydomSelectedSite) async throws {
        let payload = Payload(
            id: site.id,
            name: site.name,
            gatewayMac: site.gatewayMac
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
