import Foundation

public struct TydomGatewayCredentialFetcher: Sendable {
    public struct Dependencies: Sendable {
        public let makeSession: @Sendable () -> URLSession
        public let fetchPassword: @Sendable (_ email: String, _ password: String, _ mac: String, _ session: URLSession) async throws -> String
        public let now: @Sendable () -> Date
        public let save: @Sendable (_ gatewayId: String, _ credentials: TydomGatewayCredentials) async throws -> Void
    }

    public let dependencies: Dependencies

    public init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    public func fetchAndPersist(
        gatewayId: String,
        gatewayMac: String,
        cloudCredentials: TydomConnection.CloudCredentials
    ) async throws -> TydomGatewayCredentials {
        let session = dependencies.makeSession()
        let password = try await dependencies.fetchPassword(
            cloudCredentials.email,
            cloudCredentials.password,
            gatewayMac,
            session
        )
        session.invalidateAndCancel()
        let credentials = TydomGatewayCredentials(
            mac: gatewayMac,
            password: password,
            cachedLocalIP: nil,
            updatedAt: dependencies.now()
        )
        try await dependencies.save(gatewayId, credentials)
        return credentials
    }
}

public extension TydomGatewayCredentialFetcher.Dependencies {
    static func live(store: TydomGatewayCredentialStore) -> TydomGatewayCredentialFetcher.Dependencies {
        TydomGatewayCredentialFetcher.Dependencies(
            makeSession: {
                URLSession(configuration: .default)
            },
            fetchPassword: { email, password, mac, session in
                try await TydomCloudPasswordProvider.fetchGatewayPassword(
                    email: email,
                    password: password,
                    mac: mac,
                    session: session
                )
            },
            now: { Date() },
            save: { gatewayId, credentials in
                try await store.save(gatewayId, credentials)
            }
        )
    }
}
