import Foundation

public struct TydomConnectionResolver: Sendable {
    public typealias SiteIndexSelector = @Sendable (_ sites: [TydomCloudSitesProvider.Site]) async -> Int?

    public struct Environment: Sendable {
        public var credentialStore: TydomGatewayCredentialStore
        public var selectedSiteStore: TydomSelectedSiteStore
        public var discovery: TydomGatewayDiscovery
        public var remoteHost: String
        public var now: @Sendable () -> Date
        public var makeSession: @Sendable () -> URLSession
        public var probeConnection: @Sendable (_ configuration: TydomConnection.Configuration) async -> Bool

        public init(
            credentialStore: TydomGatewayCredentialStore,
            selectedSiteStore: TydomSelectedSiteStore,
            discovery: TydomGatewayDiscovery,
            remoteHost: String,
            now: @escaping @Sendable () -> Date,
            makeSession: @escaping @Sendable () -> URLSession,
            probeConnection: @escaping @Sendable (_ configuration: TydomConnection.Configuration) async -> Bool
        ) {
            self.credentialStore = credentialStore
            self.selectedSiteStore = selectedSiteStore
            self.discovery = discovery
            self.remoteHost = remoteHost
            self.now = now
            self.makeSession = makeSession
            self.probeConnection = probeConnection
        }

        public static func live(
            credentialService: String = "com.deltadore.tydom.gateway",
            selectedSiteService: String = "com.deltadore.tydom.selected-site",
            remoteHost: String = "mediation.tydom.com",
            now: @escaping @Sendable () -> Date = { Date() }
        ) -> Environment {
            Environment(
                credentialStore: .liveKeychain(service: credentialService, now: now),
                selectedSiteStore: .liveKeychain(service: selectedSiteService),
                discovery: TydomGatewayDiscovery(dependencies: .live()),
                remoteHost: remoteHost,
                now: now,
                makeSession: { URLSession(configuration: .default) },
                probeConnection: { configuration in
                    let connection = TydomConnection(configuration: configuration)
                    do {
                        try await connection.connect()
                        await connection.disconnect()
                        return true
                    } catch {
                        await connection.disconnect()
                        return false
                    }
                }
            )
        }
    }

    public struct Options: Sendable {
        public enum Mode: Sendable {
            case auto
            case local
            case remote
        }

        public let mode: Mode
        public let localHostOverride: String?
        public let remoteHostOverride: String?
        public let mac: String?
        public let password: String?
        public let cloudCredentials: TydomConnection.CloudCredentials?
        public let siteIndex: Int?
        public let resetSelectedSite: Bool
        public let resetSelectedSiteOnDisconnect: Bool
        public let selectedSiteAccount: String
        public let allowInsecureTLS: Bool?
        public let timeout: TimeInterval
        public let polling: TydomConnection.Configuration.Polling
        public let bonjourServices: [String]
        public let forceRemote: Bool
        public let onDecision: (@Sendable (TydomConnectionState.Decision) async -> Void)?

        public init(
            mode: Mode,
            localHostOverride: String? = nil,
            remoteHostOverride: String? = nil,
            mac: String? = nil,
            password: String? = nil,
            cloudCredentials: TydomConnection.CloudCredentials? = nil,
            siteIndex: Int? = nil,
            resetSelectedSite: Bool = false,
            resetSelectedSiteOnDisconnect: Bool = true,
            selectedSiteAccount: String = "default",
            allowInsecureTLS: Bool? = nil,
            timeout: TimeInterval = 10.0,
            polling: TydomConnection.Configuration.Polling = .init(),
            bonjourServices: [String] = ["_tydom._tcp"],
            forceRemote: Bool = false,
            onDecision: (@Sendable (TydomConnectionState.Decision) async -> Void)? = nil
        ) {
            self.mode = mode
            self.localHostOverride = localHostOverride
            self.remoteHostOverride = remoteHostOverride
            self.mac = mac
            self.password = password
            self.cloudCredentials = cloudCredentials
            self.siteIndex = siteIndex
            self.resetSelectedSite = resetSelectedSite
            self.resetSelectedSiteOnDisconnect = resetSelectedSiteOnDisconnect
            self.selectedSiteAccount = selectedSiteAccount
            self.allowInsecureTLS = allowInsecureTLS
            self.timeout = timeout
            self.polling = polling
            self.bonjourServices = bonjourServices
            self.forceRemote = forceRemote
            self.onDecision = onDecision
        }
    }

    public struct Resolution: Sendable {
        public let configuration: TydomConnection.Configuration
        public let credentials: TydomGatewayCredentials
        public let selectedSite: TydomSelectedSite?
        public let decision: TydomConnectionState.Decision?
        public let onDisconnect: (@Sendable () async -> Void)?
    }

    public enum ResolverError: Error, Sendable {
        case missingCloudCredentials
        case missingSiteSelection
        case invalidSiteIndex(Int, siteCount: Int)
        case missingGateway(String)
        case noSites
        case missingGatewayCredentials
        case missingGatewayMac
        case invalidConfiguration
    }

    private let environment: Environment

    public init(environment: Environment = .live()) {
        self.environment = environment
    }

    public func listSites(
        cloudCredentials: TydomConnection.CloudCredentials
    ) async throws -> [TydomCloudSitesProvider.Site] {
        let session = environment.makeSession()
        defer { session.invalidateAndCancel() }
        return try await TydomCloudSitesProvider.fetchSites(
            email: cloudCredentials.email,
            password: cloudCredentials.password,
            session: session
        )
    }

    public func listSitesPayload(
        cloudCredentials: TydomConnection.CloudCredentials
    ) async throws -> Data {
        let session = environment.makeSession()
        defer { session.invalidateAndCancel() }
        return try await TydomCloudSitesProvider.fetchSitesPayload(
            email: cloudCredentials.email,
            password: cloudCredentials.password,
            session: session
        )
    }

    public func makeOnDisconnect(selectedSiteAccount: String) -> @Sendable () async -> Void {
        { [store = environment.selectedSiteStore] in
            try? await store.delete(selectedSiteAccount)
        }
    }

    public func resetSelectedSite(selectedSiteAccount: String) async throws {
        try await environment.selectedSiteStore.delete(selectedSiteAccount)
    }

    public func resolve(
        _ options: Options,
        selectSiteIndex: SiteIndexSelector? = nil
    ) async throws -> Resolution {
        if options.resetSelectedSite {
            try? await environment.selectedSiteStore.delete(options.selectedSiteAccount)
        }

        let resolved = try await resolveGatewayCredentials(
            options: options,
            selectSiteIndex: selectSiteIndex
        )

        let cache = CredentialsCache(initial: resolved.credentials)
        let dependencies = makeOrchestratorDependencies(
            options: options,
            cache: cache
        )
        var state = TydomConnectionState(
            override: overrideMode(for: options.mode, forceRemote: options.forceRemote)
        )
        let orchestrator = TydomConnectionOrchestrator(dependencies: dependencies)
        await orchestrator.handle(event: .start, state: &state)

        let cachedCredentials = await cache.get()
        guard let decision = state.lastDecision,
              let latestCredentials = state.credentials ?? cachedCredentials else {
            throw ResolverError.invalidConfiguration
        }

        guard let configuration = buildConfiguration(
            decision: decision,
            credentials: latestCredentials,
            options: options
        ) else {
            throw ResolverError.invalidConfiguration
        }

        let onDisconnect = options.resetSelectedSiteOnDisconnect
            ? makeOnDisconnect(selectedSiteAccount: options.selectedSiteAccount)
            : nil

        return Resolution(
            configuration: configuration,
            credentials: latestCredentials,
            selectedSite: resolved.selectedSite,
            decision: decision,
            onDisconnect: onDisconnect
        )
    }

    private func overrideMode(
        for mode: Options.Mode,
        forceRemote: Bool
    ) -> TydomConnectionState.ModeOverride {
        if forceRemote { return .forceRemote }
        switch mode {
        case .auto:
            return .none
        case .local:
            return .forceLocal
        case .remote:
            return .forceRemote
        }
    }

    private func resolveGatewayCredentials(
        options: Options,
        selectSiteIndex: SiteIndexSelector?
    ) async throws -> ResolvedCredentials {
        let selectedSite = try await resolveSelectedSite(
            options: options,
            selectSiteIndex: selectSiteIndex
        )
        guard let selectedMac = selectedSite?.gatewayMac ?? options.mac else {
            throw ResolverError.missingGatewayMac
        }

        if let password = options.password {
            let credentials = TydomGatewayCredentials(
                mac: selectedMac,
                password: password,
                cachedLocalIP: nil,
                updatedAt: environment.now()
            )
            let gatewayId = TydomMac.normalize(selectedMac)
            try? await environment.credentialStore.save(gatewayId, credentials)
            return ResolvedCredentials(credentials: credentials, selectedSite: selectedSite)
        }

        let gatewayId = TydomMac.normalize(selectedMac)
        if let stored = try? await environment.credentialStore.load(gatewayId) {
            return ResolvedCredentials(credentials: stored, selectedSite: selectedSite)
        }

        guard let cloudCredentials = options.cloudCredentials else {
            throw ResolverError.missingGatewayCredentials
        }

        let fetcher = TydomGatewayCredentialFetcher(
            dependencies: .init(
                makeSession: environment.makeSession,
                fetchPassword: { email, password, mac, session in
                    try await TydomCloudPasswordProvider.fetchGatewayPassword(
                        email: email,
                        password: password,
                        mac: mac,
                        session: session
                    )
                },
                now: environment.now,
                save: { gatewayId, credentials in
                    try await environment.credentialStore.save(gatewayId, credentials)
                }
            )
        )
        let credentials = try await fetcher.fetchAndPersist(
            gatewayId: gatewayId,
            gatewayMac: selectedMac,
            cloudCredentials: cloudCredentials
        )
        return ResolvedCredentials(credentials: credentials, selectedSite: selectedSite)
    }

    private func resolveSelectedSite(
        options: Options,
        selectSiteIndex: SiteIndexSelector?
    ) async throws -> TydomSelectedSite? {
        if let mac = options.mac,
           options.siteIndex == nil,
           selectSiteIndex == nil {
            let manual = TydomSelectedSite(id: "manual", name: "Manual selection", gatewayMac: mac)
            try? await environment.selectedSiteStore.save(options.selectedSiteAccount, manual)
            return manual
        }

        if options.resetSelectedSite == false,
           options.siteIndex == nil,
           selectSiteIndex == nil,
           let stored = try? await environment.selectedSiteStore.load(options.selectedSiteAccount) {
            return stored
        }

        guard let cloudCredentials = options.cloudCredentials else {
            throw ResolverError.missingCloudCredentials
        }

        let sites = try await listSites(cloudCredentials: cloudCredentials)
        guard sites.isEmpty == false else {
            throw ResolverError.noSites
        }

        let chosenIndex: Int?
        if let providedIndex = options.siteIndex {
            chosenIndex = providedIndex
        } else if let selectSiteIndex {
            chosenIndex = await selectSiteIndex(sites)
        } else {
            chosenIndex = nil
        }

        guard let chosenIndex else {
            throw ResolverError.missingSiteSelection
        }

        let selected = try selectSite(from: sites, index: chosenIndex)
        try? await environment.selectedSiteStore.save(options.selectedSiteAccount, selected)
        return selected
    }

    private func selectSite(
        from sites: [TydomCloudSitesProvider.Site],
        index: Int
    ) throws -> TydomSelectedSite {
        guard sites.indices.contains(index) else {
            throw ResolverError.invalidSiteIndex(index, siteCount: sites.count)
        }
        let site = sites[index]
        guard let gateway = site.gateways.first else {
            throw ResolverError.missingGateway(site.name)
        }
        return TydomSelectedSite(id: site.id, name: site.name, gatewayMac: gateway.mac)
    }

    private func makeOrchestratorDependencies(
        options: Options,
        cache: CredentialsCache
    ) -> TydomConnectionOrchestrator.Dependencies {
        let discovery = environment.discovery
        let allowInsecureTLS = options.allowInsecureTLS
        let timeout = options.timeout
        let bonjourServices = options.bonjourServices
        let localHostOverride = options.localHostOverride
        let remoteHostOverride = options.remoteHostOverride ?? environment.remoteHost

        let connect: @Sendable (String, TydomGatewayCredentials?, TydomConnection.Configuration.Mode) async -> Bool = { host, credentials, mode in
            guard let credentials else { return false }
            let config = TydomConnection.Configuration(
                mode: mode,
                mac: credentials.mac,
                password: credentials.password,
                cloudCredentials: nil,
                allowInsecureTLS: allowInsecureTLS,
                timeout: timeout,
                polling: TydomConnection.Configuration.Polling(intervalSeconds: 0, onlyWhenActive: false)
            )
            return await self.environment.probeConnection(config)
        }

        return TydomConnectionOrchestrator.Dependencies(
            loadCredentials: {
                await cache.get()
            },
            saveCredentials: { credentials in
                let gatewayId = TydomMac.normalize(credentials.mac)
                try? await self.environment.credentialStore.save(gatewayId, credentials)
                await cache.set(credentials)
            },
            discoverLocal: {
                guard let credentials = await cache.get() else { return [] }
                let config = TydomGatewayDiscoveryConfig(
                    discoveryTimeout: min(timeout, 6),
                    probeTimeout: min(timeout, 2),
                    probeConcurrency: 12,
                    probePorts: [443],
                    bonjourServiceTypes: bonjourServices
                )
                return await discovery.discover(mac: credentials.mac, cachedIP: credentials.cachedLocalIP, config: config)
            },
            connectLocal: { host in
                let credentials = await cache.get()
                if let overrideHost = localHostOverride, overrideHost.isEmpty == false {
                    return await connect(overrideHost, credentials, .local(host: overrideHost))
                }
                return await connect(host, credentials, .local(host: host))
            },
            connectRemote: {
                let credentials = await cache.get()
                return await connect(remoteHostOverride, credentials, .remote(host: remoteHostOverride))
            },
            emitDecision: { decision in
                if let onDecision = options.onDecision {
                    await onDecision(decision)
                }
            }
        )
    }

    private func buildConfiguration(
        decision: TydomConnectionState.Decision,
        credentials: TydomGatewayCredentials,
        options: Options
    ) -> TydomConnection.Configuration? {
        switch decision.mode {
        case .local(let host):
            let resolvedHost = (options.localHostOverride?.isEmpty == false)
                ? options.localHostOverride!
                : host
            return TydomConnection.Configuration(
                mode: .local(host: resolvedHost),
                mac: credentials.mac,
                password: credentials.password,
                cloudCredentials: nil,
                allowInsecureTLS: options.allowInsecureTLS,
                timeout: options.timeout,
                polling: options.polling
            )
        case .remote(let host):
            let resolvedHost = (options.remoteHostOverride?.isEmpty == false)
                ? options.remoteHostOverride!
                : host
            return TydomConnection.Configuration(
                mode: .remote(host: resolvedHost),
                mac: credentials.mac,
                password: credentials.password,
                cloudCredentials: nil,
                allowInsecureTLS: options.allowInsecureTLS,
                timeout: options.timeout,
                polling: options.polling
            )
        }
    }
}

extension TydomConnectionResolver.ResolverError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingCloudCredentials:
            return "Missing cloud credentials."
        case .missingSiteSelection:
            return "No site selection provided."
        case .invalidSiteIndex(let index, let count):
            return "Invalid site index \(index). Available range: 0...\(max(0, count - 1))."
        case .missingGateway(let name):
            return "Selected site has no gateways: \(name)."
        case .noSites:
            return "No sites returned from cloud."
        case .missingGatewayCredentials:
            return "Missing gateway credentials."
        case .missingGatewayMac:
            return "Missing gateway MAC."
        case .invalidConfiguration:
            return "Unable to build a valid connection configuration."
        }
    }
}

private struct ResolvedCredentials: Sendable {
    let credentials: TydomGatewayCredentials
    let selectedSite: TydomSelectedSite?
}

private actor CredentialsCache {
    private var cached: TydomGatewayCredentials?

    init(initial: TydomGatewayCredentials?) {
        self.cached = initial
    }

    func get() -> TydomGatewayCredentials? { cached }
    func set(_ value: TydomGatewayCredentials?) { cached = value }
}
