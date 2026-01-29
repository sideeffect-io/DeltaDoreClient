import Foundation

public struct TydomSelectedSiteStore: Sendable {
    public var load: @Sendable (_ account: String) async throws -> TydomSelectedSite?
    public var save: @Sendable (_ account: String, _ site: TydomSelectedSite) async throws -> Void
    public var delete: @Sendable (_ account: String) async throws -> Void

    public static func inMemory(
        initial: [String: TydomSelectedSite] = [:]
    ) -> TydomSelectedSiteStore {
        let actorStore = InMemoryStore(storage: initial)
        return TydomSelectedSiteStore(
            load: { account in
                await actorStore.load(account)
            },
            save: { account, site in
                await actorStore.save(account, site)
            },
            delete: { account in
                await actorStore.delete(account)
            }
        )
    }
}

private actor InMemoryStore {
    private var storage: [String: TydomSelectedSite]

    init(storage: [String: TydomSelectedSite]) {
        self.storage = storage
    }

    func load(_ account: String) -> TydomSelectedSite? {
        storage[account]
    }

    func save(_ account: String, _ site: TydomSelectedSite) {
        storage[account] = site
    }

    func delete(_ account: String) {
        storage.removeValue(forKey: account)
    }
}
