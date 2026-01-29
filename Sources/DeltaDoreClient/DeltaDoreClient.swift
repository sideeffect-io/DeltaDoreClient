import Foundation

/// High-level entry point that wires the connection resolver and connection factory.
///
/// This keeps app code minimal while still allowing dependency injection for tests
/// or platform-specific customization.
///
/// Example:
/// ```swift
/// let client = DeltaDoreClient.live()
/// let options = DeltaDoreClient.Options(
///     mode: .auto,
///     cloudCredentials: .init(email: "user@example.com", password: "secret")
/// )
/// let session = try await client.connect(
///     options: options,
///     selectSiteIndex: { sites in
///         // Present UI and return the chosen index.
///         return 0
///     }
/// )
/// let connection = session.connection
/// ```
public struct DeltaDoreClient: Sendable {
    public typealias Options = TydomConnectionResolver.Options
    public typealias SiteIndexSelector = TydomConnectionResolver.SiteIndexSelector
    public typealias Resolution = TydomConnectionResolver.Resolution
    public typealias Site = TydomCloudSitesProvider.Site

    public struct ConnectionSession: Sendable {
        public let connection: TydomConnection
        public let resolution: Resolution
    }

    public struct Dependencies: Sendable {
        public var resolve: @Sendable (Options, SiteIndexSelector?) async throws -> Resolution
        public var listSites: @Sendable (TydomConnection.CloudCredentials) async throws -> [Site]
        public var listSitesPayload: @Sendable (TydomConnection.CloudCredentials) async throws -> Data
        public var resetSelectedSite: @Sendable (String) async throws -> Void
        public var makeConnection: @Sendable (Resolution) -> TydomConnection
        public var connect: @Sendable (TydomConnection) async throws -> Void

        public init(
            resolve: @escaping @Sendable (Options, SiteIndexSelector?) async throws -> Resolution,
            listSites: @escaping @Sendable (TydomConnection.CloudCredentials) async throws -> [Site],
            listSitesPayload: @escaping @Sendable (TydomConnection.CloudCredentials) async throws -> Data,
            resetSelectedSite: @escaping @Sendable (String) async throws -> Void,
            makeConnection: @escaping @Sendable (Resolution) -> TydomConnection,
            connect: @escaping @Sendable (TydomConnection) async throws -> Void
        ) {
            self.resolve = resolve
            self.listSites = listSites
            self.listSitesPayload = listSitesPayload
            self.resetSelectedSite = resetSelectedSite
            self.makeConnection = makeConnection
            self.connect = connect
        }

        public static func live(
            credentialService: String = "com.deltadore.tydom.gateway",
            selectedSiteService: String = "com.deltadore.tydom.selected-site",
            remoteHost: String = "mediation.tydom.com",
            now: @escaping @Sendable () -> Date = { Date() }
        ) -> Dependencies {
            let resolver = TydomConnectionResolver(
                environment: .live(
                    credentialService: credentialService,
                    selectedSiteService: selectedSiteService,
                    remoteHost: remoteHost,
                    now: now
                )
            )
            return Dependencies(
                resolve: { options, selectSiteIndex in
                    try await resolver.resolve(options, selectSiteIndex: selectSiteIndex)
                },
                listSites: { credentials in
                    try await resolver.listSites(cloudCredentials: credentials)
                },
                listSitesPayload: { credentials in
                    try await resolver.listSitesPayload(cloudCredentials: credentials)
                },
                resetSelectedSite: { account in
                    try await resolver.resetSelectedSite(selectedSiteAccount: account)
                },
                makeConnection: { resolution in
                    TydomConnection(
                        configuration: resolution.configuration,
                        onDisconnect: resolution.onDisconnect
                    )
                },
                connect: { connection in
                    try await connection.connect()
                }
            )
        }
    }

    private let dependencies: Dependencies

    public init(dependencies: Dependencies = .live()) {
        self.dependencies = dependencies
    }

    public static func live(
        credentialService: String = "com.deltadore.tydom.gateway",
        selectedSiteService: String = "com.deltadore.tydom.selected-site",
        remoteHost: String = "mediation.tydom.com",
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> DeltaDoreClient {
        DeltaDoreClient(
            dependencies: .live(
                credentialService: credentialService,
                selectedSiteService: selectedSiteService,
                remoteHost: remoteHost,
                now: now
            )
        )
    }

    /// Resolves the connection configuration and credentials, using the stored site selection when available.
    public func resolve(
        options: Options,
        selectSiteIndex: SiteIndexSelector? = nil
    ) async throws -> Resolution {
        try await dependencies.resolve(options, selectSiteIndex)
    }

    /// Lists cloud sites for the provided credentials.
    public func listSites(
        cloudCredentials: TydomConnection.CloudCredentials
    ) async throws -> [Site] {
        try await dependencies.listSites(cloudCredentials)
    }

    /// Returns the raw JSON payload from the cloud site list endpoint.
    public func listSitesPayload(
        cloudCredentials: TydomConnection.CloudCredentials
    ) async throws -> Data {
        try await dependencies.listSitesPayload(cloudCredentials)
    }

    /// Deletes the stored site selection for the given account.
    public func resetSelectedSite(selectedSiteAccount: String) async throws {
        try await dependencies.resetSelectedSite(selectedSiteAccount)
    }

    /// Resolves the connection configuration and creates a `TydomConnection` without connecting.
    public func makeConnection(
        options: Options,
        selectSiteIndex: SiteIndexSelector? = nil
    ) async throws -> ConnectionSession {
        let resolution = try await resolve(options: options, selectSiteIndex: selectSiteIndex)
        let connection = dependencies.makeConnection(resolution)
        return ConnectionSession(connection: connection, resolution: resolution)
    }

    /// Resolves, creates, and connects a `TydomConnection`.
    public func connect(
        options: Options,
        selectSiteIndex: SiteIndexSelector? = nil
    ) async throws -> ConnectionSession {
        let session = try await makeConnection(options: options, selectSiteIndex: selectSiteIndex)
        try await dependencies.connect(session.connection)
        return session
    }
}
