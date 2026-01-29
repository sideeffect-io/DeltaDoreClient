import Foundation

public struct TydomGatewayCredentialStore: Sendable {
    public var load: @Sendable (_ gatewayId: String) async throws -> TydomGatewayCredentials?
    public var save: @Sendable (_ gatewayId: String, _ credentials: TydomGatewayCredentials) async throws -> Void
    public var delete: @Sendable (_ gatewayId: String) async throws -> Void

    public static func inMemory(
        initial: [String: TydomGatewayCredentials] = [:]
    ) -> TydomGatewayCredentialStore {
        let actorStore = InMemoryStore(storage: initial)
        return TydomGatewayCredentialStore(
            load: { gatewayId in
                await actorStore.load(gatewayId)
            },
            save: { gatewayId, credentials in
                await actorStore.save(gatewayId, credentials)
            },
            delete: { gatewayId in
                await actorStore.delete(gatewayId)
            }
        )
    }
}

private actor InMemoryStore {
    private var storage: [String: TydomGatewayCredentials]

    init(storage: [String: TydomGatewayCredentials]) {
        self.storage = storage
    }

    func load(_ gatewayId: String) -> TydomGatewayCredentials? {
        storage[gatewayId]
    }

    func save(_ gatewayId: String, _ credentials: TydomGatewayCredentials) {
        storage[gatewayId] = credentials
    }

    func delete(_ gatewayId: String) {
        storage.removeValue(forKey: gatewayId)
    }
}
