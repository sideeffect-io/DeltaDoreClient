import Foundation
import DeltaDoreClient

func runCLI(
    options: CLIOptions,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) async {
    let connection = TydomConnection(
        configuration: options.configuration,
        log: { message in
            Task { await stderr.writeLine("[connection] \(message)") }
        },
        onDisconnect: options.onDisconnect
    )
    await connection.setAppActive(true)

    do {
        try await connection.connect()
    } catch {
        await stderr.writeLine("Failed to connect: \(error)")
        return
    }

    let initialPingOk = await send(command: .ping(), connection: connection, stderr: stderr)
    guard initialPingOk else {
        await stderr.writeLine("Connection closed before initial ping.")
        await connection.disconnect()
        return
    }

    let messageTask = Task {
        let stream = await connection.decodedMessages(logger: { message in
            Task { await stderr.writeLine("[polling] \(message)") }
        })
        for await message in stream {
            let output = render(message: message)
            await stdout.writeLine(output)
        }
    }

    await stdout.writeLine("Connected. Type `help` to list commands.")

    inputLoop: for await line in stdinLines() {
        guard let result = parseInputCommand(line) else { continue }
        switch result {
        case .failure(let error):
            await stderr.writeLine(error.message)
        case .success(let command):
            switch command {
            case .help:
                await stdout.writeLine(commandHelpText())
            case .quit:
                break inputLoop
            case .setActive(let isActive):
                await connection.setAppActive(isActive)
                await stdout.writeLine("App active set to \(isActive).")
            case .send(let command):
                await send(command: command, connection: connection, stderr: stderr)
            case .sendMany(let commands):
                for command in commands {
                    await send(command: command, connection: connection, stderr: stderr)
                }
            case .sendRaw(let raw):
                do {
                    try await connection.send(text: raw)
                } catch {
                    await stderr.writeLine("Send failed: \(error)")
                }
            }
        }
    }

    await connection.disconnect()
    messageTask.cancel()
    await stdout.writeLine("Disconnected.")
}

func resolveAutoConfiguration(
    options: AutoOptions,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) async -> CLIOptions? {
    let store = TydomGatewayCredentialStore.liveKeychain(service: "com.deltadore.tydom.cli")
    let selectedSiteStore = TydomSelectedSiteStore.liveKeychain(service: "com.deltadore.tydom.cli.site-selection")
    let selectedSiteAccount = "default"
    let remoteHost = options.remoteHost ?? "mediation.tydom.com"
    let onDisconnect: (@Sendable () async -> Void) = {
        try? await selectedSiteStore.delete(selectedSiteAccount)
    }

    func makePolling() -> TydomConnection.Configuration.Polling {
        TydomConnection.Configuration.Polling(
            intervalSeconds: options.pollInterval,
            onlyWhenActive: options.pollOnlyActive
        )
    }

    func localConfig(
        mac: String,
        password: String,
        host: String,
        polling: TydomConnection.Configuration.Polling
    ) -> TydomConnection.Configuration {
        TydomConnection.Configuration(
            mode: .local(host: host),
            mac: mac,
            password: password,
            cloudCredentials: nil,
            allowInsecureTLS: options.allowInsecureTLS,
            timeout: options.timeout,
            polling: polling
        )
    }

    func remoteConfig(
        mac: String,
        password: String,
        polling: TydomConnection.Configuration.Polling
    ) -> TydomConnection.Configuration {
        TydomConnection.Configuration(
            mode: .remote(host: remoteHost),
            mac: mac,
            password: password,
            cloudCredentials: nil,
            allowInsecureTLS: options.allowInsecureTLS,
            timeout: options.timeout,
            polling: polling
        )
    }

    func probeLocal(mac: String, password: String, host: String) async -> Bool {
        let probePolling = TydomConnection.Configuration.Polling(intervalSeconds: 0, onlyWhenActive: false)
        let config = localConfig(mac: mac, password: password, host: host, polling: probePolling)
        let connection = TydomConnection(configuration: config)
        do {
            try await connection.connect()
            await connection.disconnect()
            return true
        } catch {
            await connection.disconnect()
            return false
        }
    }

    guard let stored = await resolveGatewayCredentials(
        mac: options.mac,
        cloudCredentials: options.cloudCredentials,
        siteIndex: options.siteIndex,
        listSites: options.listSites,
        dumpSitesResponse: options.dumpSitesResponse,
        resetSite: options.resetSite,
        selectedSiteStore: selectedSiteStore,
        selectedSiteAccount: selectedSiteAccount,
        store: store,
        stdout: stdout,
        stderr: stderr
    ) else {
        return nil
    }

    if options.forceRemote {
        await stderr.writeLine("Local connection disabled by --no-local. Falling back to remote.")
        return CLIOptions(
            configuration: remoteConfig(mac: stored.mac, password: stored.password, polling: makePolling()),
            onDisconnect: onDisconnect
        )
    }

    if let cachedIP = stored.cachedLocalIP, cachedIP.isEmpty == false {
        await stdout.writeLine("Trying cached IP \(cachedIP)...")
        if await probeLocal(mac: stored.mac, password: stored.password, host: cachedIP) {
            return CLIOptions(
                configuration: localConfig(mac: stored.mac, password: stored.password, host: cachedIP, polling: makePolling()),
                onDisconnect: onDisconnect
            )
        }
        await stderr.writeLine("Cached IP failed, running discovery.")
    }

    let discovery = TydomGatewayDiscovery(dependencies: .live())
    let discoveryConfig = TydomGatewayDiscoveryConfig(
        discoveryTimeout: min(options.timeout, 6),
        probeTimeout: min(options.timeout, 2),
        probeConcurrency: 12,
        probePorts: [443],
        bonjourServiceTypes: options.bonjourServices
    )
    let candidates = await discovery.discover(mac: stored.mac, cachedIP: nil, config: discoveryConfig)
    for candidate in candidates {
        await stdout.writeLine("Probing \(candidate.host) (\(candidate.method.rawValue))...")
        if await probeLocal(mac: stored.mac, password: stored.password, host: candidate.host) {
            let updated = TydomGatewayCredentials(
                mac: stored.mac,
                password: stored.password,
                cachedLocalIP: candidate.host,
                updatedAt: Date()
            )
            do {
                let gatewayId = TydomMac.normalize(stored.mac)
                try await store.save(gatewayId, updated)
            } catch {
                await stderr.writeLine("Failed to persist cached IP: \(error)")
            }
            return CLIOptions(
                configuration: localConfig(mac: stored.mac, password: stored.password, host: candidate.host, polling: makePolling()),
                onDisconnect: onDisconnect
            )
        }
    }

    await stderr.writeLine("Local connection failed, falling back to remote.")
    return CLIOptions(
        configuration: remoteConfig(mac: stored.mac, password: stored.password, polling: makePolling()),
        onDisconnect: onDisconnect
    )
}

func resolveExplicitConfiguration(
    options: ResolveOptions,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) async -> CLIOptions? {
    let store = TydomGatewayCredentialStore.liveKeychain(service: "com.deltadore.tydom.cli")
    let selectedSiteStore = TydomSelectedSiteStore.liveKeychain(service: "com.deltadore.tydom.cli.site-selection")
    let selectedSiteAccount = "default"
    let credentialsCache = CredentialsCache()
    let onDisconnect: (@Sendable () async -> Void) = {
        try? await selectedSiteStore.delete(selectedSiteAccount)
    }
    let dependencies = makeOrchestratorDependencies(
        mode: options.mode,
        localHostOverride: options.mode == "local" ? options.host : nil,
        remoteHostOverride: options.mode == "remote" ? options.host : nil,
        mac: options.mac,
        password: options.password,
        cloudCredentials: options.cloudCredentials,
        siteIndex: options.siteIndex,
        listSites: options.listSites,
        dumpSitesResponse: options.dumpSitesResponse,
        bonjourServices: options.bonjourServices,
        timeout: options.timeout,
        polling: TydomConnection.Configuration.Polling(
            intervalSeconds: options.pollInterval,
            onlyWhenActive: options.pollOnlyActive
        ),
        allowInsecureTLS: options.allowInsecureTLS,
        resetSite: options.resetSite,
        selectedSiteStore: selectedSiteStore,
        selectedSiteAccount: selectedSiteAccount,
        store: store,
        cache: credentialsCache,
        stdout: stdout,
        stderr: stderr
    )

    var state = TydomConnectionState(
        override: options.mode == "remote" ? .forceRemote : .forceLocal
    )
    let orchestrator = TydomConnectionOrchestrator(dependencies: dependencies)
    await orchestrator.handle(event: .start, state: &state)
    guard let resolved = state.lastDecision, let credentials = state.credentials else {
        return nil
    }
    guard let configuration = buildConfiguration(
        decision: resolved,
        mac: credentials.mac,
        password: credentials.password,
        allowInsecureTLS: options.allowInsecureTLS,
        timeout: options.timeout,
        polling: TydomConnection.Configuration.Polling(
            intervalSeconds: options.pollInterval,
            onlyWhenActive: options.pollOnlyActive
        ),
        localHostOverride: options.mode == "local" ? options.host : nil,
        remoteHostOverride: options.mode == "remote" ? options.host : nil
    ) else {
        return nil
    }
    return CLIOptions(configuration: configuration, onDisconnect: onDisconnect)
}

private actor CredentialsCache {
    private var cached: TydomGatewayCredentials?

    func get() -> TydomGatewayCredentials? { cached }
    func set(_ value: TydomGatewayCredentials?) { cached = value }
}

private func makeOrchestratorDependencies(
    mode: String,
    localHostOverride: String?,
    remoteHostOverride: String?,
    mac: String?,
    password: String?,
    cloudCredentials: TydomConnection.CloudCredentials?,
    siteIndex: Int?,
    listSites: Bool,
    dumpSitesResponse: Bool,
    bonjourServices: [String],
    timeout: TimeInterval,
    polling: TydomConnection.Configuration.Polling,
    allowInsecureTLS: Bool?,
    resetSite: Bool,
    selectedSiteStore: TydomSelectedSiteStore,
    selectedSiteAccount: String,
    store: TydomGatewayCredentialStore,
    cache: CredentialsCache,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) -> TydomConnectionOrchestrator.Dependencies {
    let discovery = TydomGatewayDiscovery(dependencies: .live())

    let resolveCredentials: @Sendable () async -> TydomGatewayCredentials? = {
        if let cached = await cache.get() { return cached }
        if let mac, let password {
            let credentials = TydomGatewayCredentials(
                mac: mac,
                password: password,
                cachedLocalIP: nil,
                updatedAt: Date()
            )
            let gatewayId = TydomMac.normalize(mac)
            try? await store.save(gatewayId, credentials)
            await cache.set(credentials)
            return credentials
        }
        if let mac {
            let gatewayId = TydomMac.normalize(mac)
            if let stored = try? await store.load(gatewayId) {
                await cache.set(stored)
                return stored
            }
        }
        let resolved = await resolveGatewayCredentials(
            mac: mac,
            cloudCredentials: cloudCredentials,
            siteIndex: siteIndex,
            listSites: listSites,
            dumpSitesResponse: dumpSitesResponse,
            resetSite: resetSite,
            selectedSiteStore: selectedSiteStore,
            selectedSiteAccount: selectedSiteAccount,
            store: store,
            stdout: stdout,
            stderr: stderr
        )
        await cache.set(resolved)
        return resolved
    }

    let connect: @Sendable (String, TydomGatewayCredentials?, TydomConnection.Configuration.Mode) async -> Bool = { host, credentials, mode in
        guard let credentials else { return false }
        let config = TydomConnection.Configuration(
            mode: mode,
            mac: credentials.mac,
            password: credentials.password,
            cloudCredentials: nil,
            allowInsecureTLS: allowInsecureTLS,
            timeout: timeout,
            polling: polling
        )
        let connection = TydomConnection(configuration: config)
        do {
            try await connection.connect()
            await connection.disconnect()
            return true
        } catch {
            await connection.disconnect()
            return false
        }
    }

    return TydomConnectionOrchestrator.Dependencies(
        loadCredentials: {
            await resolveCredentials()
        },
        saveCredentials: { credentials in
            let gatewayId = TydomMac.normalize(credentials.mac)
            try? await store.save(gatewayId, credentials)
            await cache.set(credentials)
        },
        discoverLocal: {
            guard let credentials = await resolveCredentials() else { return [] }
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
            let credentials = await resolveCredentials()
            if let overrideHost = localHostOverride, overrideHost.isEmpty == false {
                return await connect(overrideHost, credentials, .local(host: overrideHost))
            }
            return await connect(host, credentials, .local(host: host))
        },
        connectRemote: {
            let credentials = await resolveCredentials()
            let remoteHost = remoteHostOverride ?? "mediation.tydom.com"
            return await connect(remoteHost, credentials, .remote(host: remoteHost))
        },
        emitDecision: { decision in
            await stdout.writeLine("Decision: \(decision.reason.rawValue) -> \(decision.mode)")
        }
    )
}

private func buildConfiguration(
    decision: TydomConnectionState.Decision,
    mac: String,
    password: String,
    allowInsecureTLS: Bool?,
    timeout: TimeInterval,
    polling: TydomConnection.Configuration.Polling,
    localHostOverride: String?,
    remoteHostOverride: String?
) -> TydomConnection.Configuration? {
    switch decision.mode {
    case .local(let host):
        let resolvedHost = (localHostOverride?.isEmpty == false) ? localHostOverride! : host
        return TydomConnection.Configuration(
            mode: .local(host: resolvedHost),
            mac: mac,
            password: password,
            cloudCredentials: nil,
            allowInsecureTLS: allowInsecureTLS,
            timeout: timeout,
            polling: polling
        )
    case .remote(let host):
        let resolvedHost = (remoteHostOverride?.isEmpty == false) ? remoteHostOverride! : host
        return TydomConnection.Configuration(
            mode: .remote(host: resolvedHost),
            mac: mac,
            password: password,
            cloudCredentials: nil,
            allowInsecureTLS: allowInsecureTLS,
            timeout: timeout,
            polling: polling
        )
    }
}

@discardableResult
private func send(
    command: TydomCommand,
    connection: TydomConnection,
    stderr: ConsoleWriter
) async -> Bool {
    do {
        try await connection.send(text: command.request)
        return true
    } catch {
        await stderr.writeLine("Send failed: \(error)")
        return false
    }
}

private func stdinLines() -> AsyncStream<String> {
    AsyncStream { continuation in
        let task = Task {
            var buffer = Data()
            do {
                for try await byte in FileHandle.standardInput.bytes {
                    if Task.isCancelled { break }
                    if byte == 10 { // \n
                        if let line = String(data: buffer, encoding: .utf8) {
                            continuation.yield(line)
                        }
                        buffer.removeAll(keepingCapacity: true)
                        continue
                    }
                    if byte != 13 { // ignore \r
                        buffer.append(byte)
                    }
                }
            } catch {
                // stdin stream failed; fall through to finalize
            }
            if buffer.isEmpty == false, let line = String(data: buffer, encoding: .utf8) {
                continuation.yield(line)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}
