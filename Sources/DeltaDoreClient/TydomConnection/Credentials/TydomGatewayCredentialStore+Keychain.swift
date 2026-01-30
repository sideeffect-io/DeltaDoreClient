import Foundation

#if canImport(Security)
import Security

public extension TydomGatewayCredentialStore {
    static func liveKeychain(
        service: String = "io.sideeffect.deltadoreclient.gateway",
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> TydomGatewayCredentialStore {
        let store = KeychainStore<Payload>(service: service)
        return TydomGatewayCredentialStore(
            load: { gatewayId in
                guard let payload = try await store.load(account: gatewayId) else {
                    return nil
                }
                return TydomGatewayCredentials(
                    mac: payload.mac,
                    password: payload.password,
                    cachedLocalIP: payload.cachedLocalIP,
                    updatedAt: payload.updatedAt
                )
            },
            save: { gatewayId, credentials in
                let updated = TydomGatewayCredentials(
                    mac: credentials.mac,
                    password: credentials.password,
                    cachedLocalIP: credentials.cachedLocalIP,
                    updatedAt: now()
                )
                let payload = Payload(
                    mac: updated.mac,
                    password: updated.password,
                    cachedLocalIP: updated.cachedLocalIP,
                    updatedAt: updated.updatedAt
                )
                try await store.save(account: gatewayId, value: payload)
            },
            delete: { gatewayId in
                try await store.delete(account: gatewayId)
            }
        )
    }
}

private struct Payload: Codable {
    let mac: String
    let password: String
    let cachedLocalIP: String?
    let updatedAt: Date
}
#endif
