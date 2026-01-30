import Foundation

#if canImport(Security)
import Security

public extension TydomSelectedSiteStore {
    static func liveKeychain(
        service: String = "io.sideeffect.deltadoreclient.selected-site"
    ) -> TydomSelectedSiteStore {
        let store = KeychainStore<Payload>(service: service)
        return TydomSelectedSiteStore(
            load: { account in
                guard let payload = try await store.load(account: account) else {
                    return nil
                }
                return TydomSelectedSite(
                    id: payload.id,
                    name: payload.name,
                    gatewayMac: payload.gatewayMac
                )
            },
            save: { account, site in
                let payload = Payload(
                    id: site.id,
                    name: site.name,
                    gatewayMac: site.gatewayMac
                )
                try await store.save(account: account, value: payload)
            },
            delete: { account in
                try await store.delete(account: account)
            }
        )
    }
}

private struct Payload: Codable {
    let id: String
    let name: String
    let gatewayMac: String
}
#endif
