import Foundation
import DeltaDoreClient

@main
struct DeltaDoreCLI {
    static func main() async {
        let stdout = ConsoleWriter(handle: .standardOutput)
        let stderr = ConsoleWriter(handle: .standardError)

        let action = parseArguments(Array(CommandLine.arguments.dropFirst()))
        switch action {
        case .help(let text):
            await stdout.writeLine(text)
            return
        case .failure(let message):
            await stderr.writeLine(message)
            await stdout.writeLine(helpText())
            return
        case .run(let options):
            await runCLI(options: options, stdout: stdout, stderr: stderr)
        case .runAuto(let options):
            guard let configuration = await resolveAutoConfiguration(
                options: options,
                stdout: stdout,
                stderr: stderr
            ) else {
                return
            }
            await runCLI(options: CLIOptions(configuration: configuration), stdout: stdout, stderr: stderr)
        case .runResolved(let options):
            guard let configuration = await resolveExplicitConfiguration(
                options: options,
                stdout: stdout,
                stderr: stderr
            ) else {
                return
            }
            await runCLI(options: CLIOptions(configuration: configuration), stdout: stdout, stderr: stderr)
        }
    }
}

private enum StartupAction: Sendable {
    case run(CLIOptions)
    case runAuto(AutoOptions)
    case runResolved(ResolveOptions)
    case help(String)
    case failure(String)
}

private struct CLIOptions: Sendable {
    let configuration: TydomConnection.Configuration
}

private struct AutoOptions: Sendable {
    let mac: String?
    let cloudCredentials: TydomConnection.CloudCredentials?
    let siteIndex: Int?
    let bonjourServices: [String]
    let timeout: TimeInterval
    let pollInterval: Int
    let pollOnlyActive: Bool
    let allowInsecureTLS: Bool?
    let remoteHost: String?
    let listSites: Bool
    let forceRemote: Bool
    let dumpSitesResponse: Bool
}

private struct ResolveOptions: Sendable {
    let mode: String
    let host: String?
    let mac: String?
    let password: String?
    let cloudCredentials: TydomConnection.CloudCredentials?
    let siteIndex: Int?
    let listSites: Bool
    let timeout: TimeInterval
    let pollInterval: Int
    let pollOnlyActive: Bool
    let allowInsecureTLS: Bool?
    let dumpSitesResponse: Bool
}

private enum CLICommand: Sendable {
    case help
    case quit
    case setActive(Bool)
    case send(TydomCommand)
    case sendMany([TydomCommand])
    case sendRaw(String)
}

private struct CLIParseError: Error, Sendable {
    let message: String
}

private actor ConsoleWriter {
    private let handle: FileHandle

    init(handle: FileHandle) {
        self.handle = handle
    }

    func writeLine(_ line: String) {
        write(line + "\n")
    }

    func write(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        handle.write(data)
    }
}

private func runCLI(
    options: CLIOptions,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) async {
    let connection = TydomConnection(
        configuration: options.configuration,
        log: { message in
            Task { await stderr.writeLine("[connection] \(message)") }
        }
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

private func resolveAutoConfiguration(
    options: AutoOptions,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) async -> TydomConnection.Configuration? {
    let store = TydomGatewayCredentialStore.liveKeychain(service: "com.deltadore.tydom.cli")
    let remoteHost = options.remoteHost ?? "mediation.tydom.com"

    func makePolling() -> TydomConnection.Configuration.Polling {
        TydomConnection.Configuration.Polling(
            intervalSeconds: options.pollInterval,
            onlyWhenActive: options.pollOnlyActive
        )
    }

    func localConfig(mac: String, password: String, host: String, polling: TydomConnection.Configuration.Polling) -> TydomConnection.Configuration {
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

    func remoteConfig(mac: String, password: String, polling: TydomConnection.Configuration.Polling) -> TydomConnection.Configuration {
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
        store: store,
        stdout: stdout,
        stderr: stderr
    ) else {
        return nil
    }

    if options.forceRemote {
        await stderr.writeLine("Local connection disabled by --no-local. Falling back to remote.")
        return remoteConfig(mac: stored.mac, password: stored.password, polling: makePolling())
    }

    if let cachedIP = stored.cachedLocalIP, cachedIP.isEmpty == false {
        await stdout.writeLine("Trying cached IP \(cachedIP)...")
        if await probeLocal(mac: stored.mac, password: stored.password, host: cachedIP) {
            return localConfig(mac: stored.mac, password: stored.password, host: cachedIP, polling: makePolling())
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
            return localConfig(mac: stored.mac, password: stored.password, host: candidate.host, polling: makePolling())
        }
    }

    await stderr.writeLine("Local connection failed, falling back to remote.")
    return remoteConfig(mac: stored.mac, password: stored.password, polling: makePolling())
}

private func resolveExplicitConfiguration(
    options: ResolveOptions,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) async -> TydomConnection.Configuration? {
    let store = TydomGatewayCredentialStore.liveKeychain(service: "com.deltadore.tydom.cli")
    guard let stored = await resolveGatewayCredentials(
        mac: options.mac,
        cloudCredentials: options.cloudCredentials,
        siteIndex: options.siteIndex,
        listSites: options.listSites,
        dumpSitesResponse: options.dumpSitesResponse,
        store: store,
        stdout: stdout,
        stderr: stderr
    ) else {
        return nil
    }

    let polling = TydomConnection.Configuration.Polling(
        intervalSeconds: options.pollInterval,
        onlyWhenActive: options.pollOnlyActive
    )

    switch options.mode {
    case "local":
        guard let host = options.host else {
            await stderr.writeLine("Missing required --host for local mode.")
            return nil
        }
        return TydomConnection.Configuration(
            mode: .local(host: host),
            mac: stored.mac,
            password: stored.password,
            cloudCredentials: nil,
            allowInsecureTLS: options.allowInsecureTLS,
            timeout: options.timeout,
            polling: polling
        )
    case "remote":
        let host = options.host ?? "mediation.tydom.com"
        return TydomConnection.Configuration(
            mode: .remote(host: host),
            mac: stored.mac,
            password: stored.password,
            cloudCredentials: nil,
            allowInsecureTLS: options.allowInsecureTLS,
            timeout: options.timeout,
            polling: polling
        )
    default:
        await stderr.writeLine("Invalid --mode value. Use local, remote, or auto.")
        return nil
    }
}

private func resolveGatewayCredentials(
    mac: String?,
    cloudCredentials: TydomConnection.CloudCredentials?,
    siteIndex: Int?,
    listSites: Bool,
    dumpSitesResponse: Bool,
    store: TydomGatewayCredentialStore,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) async -> TydomGatewayCredentials? {
    var selectedMac = mac
    if selectedMac == nil {
        guard let cloudCredentials else {
            await stderr.writeLine("Missing --mac. Provide --cloud-email and --cloud-password to fetch sites.")
            return nil
        }
        let session = URLSession(configuration: .default)
        do {
            if dumpSitesResponse {
                let payload = try await TydomCloudSitesProvider.fetchSitesPayload(
                    email: cloudCredentials.email,
                    password: cloudCredentials.password,
                    session: session
                )
                session.invalidateAndCancel()
                let output = String(data: payload, encoding: .utf8) ?? "<non-utf8>"
                await stdout.writeLine(output)
                return nil
            }
            let sites = try await TydomCloudSitesProvider.fetchSites(
                email: cloudCredentials.email,
                password: cloudCredentials.password,
                session: session
            )
            session.invalidateAndCancel()
            guard sites.isEmpty == false else {
                await stderr.writeLine("No sites returned from cloud.")
                return nil
            }
            if listSites {
                await printSites(sites, stdout: stdout)
                return nil
            }
            let index: Int
            if let providedIndex = siteIndex {
                guard sites.indices.contains(providedIndex) else {
                    await stderr.writeLine("Invalid --site-index \(providedIndex). Available range: 0...\(max(0, sites.count - 1)).")
                    return nil
                }
                index = providedIndex
            } else {
                guard let selection = await chooseSiteIndex(sites, stdout: stdout, stderr: stderr) else {
                    return nil
                }
                index = selection
            }
            let site = sites[index]
            guard let gateway = site.gateways.first else {
                await stderr.writeLine("Selected site has no gateways.")
                return nil
            }
            selectedMac = gateway.mac
            await stdout.writeLine("Selected site: \(site.name) (gateway: \(gateway.mac))")
        } catch {
            session.invalidateAndCancel()
            await stderr.writeLine("Failed to fetch sites: \(error)")
            return nil
        }
    }

    guard let selectedMac else {
        await stderr.writeLine("Missing gateway MAC.")
        return nil
    }

    let gatewayId = TydomMac.normalize(selectedMac)
    var credentials: TydomGatewayCredentials?
    do {
        credentials = try await store.load(gatewayId)
    } catch {
        await stderr.writeLine("Failed to load credentials: \(error)")
    }

    if credentials == nil {
        guard let cloudCredentials else {
            await stderr.writeLine("No stored credentials. Provide --cloud-email and --cloud-password to fetch them.")
            return nil
        }
        let fetcher = TydomGatewayCredentialFetcher(dependencies: .live(store: store))
        do {
            credentials = try await fetcher.fetchAndPersist(
                gatewayId: gatewayId,
                gatewayMac: selectedMac,
                cloudCredentials: cloudCredentials
            )
            await stdout.writeLine("Fetched and stored gateway credentials.")
        } catch {
            await stderr.writeLine("Failed to fetch gateway credentials: \(error)")
            return nil
        }
    }

    guard let stored = credentials else {
        await stderr.writeLine("Missing gateway credentials.")
        return nil
    }
    return stored
}

private func chooseSiteIndex(
    _ sites: [TydomCloudSitesProvider.Site],
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) async -> Int? {
    await printSites(sites, stdout: stdout)
    await stdout.writeLine("Choose a site index:")
    guard let line = readLine(), let selection = Int(line), sites.indices.contains(selection) else {
        await stderr.writeLine("Invalid selection.")
        return nil
    }
    return selection
}

private func printSites(
    _ sites: [TydomCloudSitesProvider.Site],
    stdout: ConsoleWriter
) async {
    var lines: [String] = []
    lines.append("Available sites:")
    for (index, site) in sites.enumerated() {
        let gatewayLabel = site.gateways.map { $0.mac }.joined(separator: ", ")
        let gatewaysText = gatewayLabel.isEmpty ? "no gateways" : gatewayLabel
        lines.append("  [\(index)] \(site.name) - \(gatewaysText)")
    }
    await stdout.writeLine(lines.joined(separator: "\n"))
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
        let task = Task.detached {
            while let line = readLine() {
                continuation.yield(line)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}

private func parseArguments(_ args: [String]) -> StartupAction {
    var mode: String = "local"
    var host: String?
    var mac: String?
    var password: String?
    var cloudEmail: String?
    var cloudPassword: String?
    var siteIndex: Int?
    var bonjourServices: [String] = []
    var timeout: TimeInterval = 10.0
    var pollInterval: Int = 60
    var pollOnlyActive: Bool = true
    var allowInsecureTLS: Bool?
    var listSites: Bool = false
    var forceRemote: Bool = false
    var dumpSitesResponse: Bool = false

    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--help", "-h":
            return .help(helpText())
        case "--mode":
            index += 1
            guard index < args.count else { return .failure("Missing value for --mode.") }
            mode = args[index].lowercased()
        case "--host":
            index += 1
            guard index < args.count else { return .failure("Missing value for --host.") }
            host = args[index]
        case "--mac":
            index += 1
            guard index < args.count else { return .failure("Missing value for --mac.") }
            mac = args[index]
        case "--password":
            index += 1
            guard index < args.count else { return .failure("Missing value for --password.") }
            password = args[index]
        case "--cloud-email":
            index += 1
            guard index < args.count else { return .failure("Missing value for --cloud-email.") }
            cloudEmail = args[index]
        case "--cloud-password":
            index += 1
            guard index < args.count else { return .failure("Missing value for --cloud-password.") }
            cloudPassword = args[index]
        case "--site-index":
            index += 1
            guard index < args.count, let value = Int(args[index]) else {
                return .failure("Invalid value for --site-index.")
            }
            siteIndex = value
        case "--bonjour-service":
            index += 1
            guard index < args.count else { return .failure("Missing value for --bonjour-service.") }
            bonjourServices.append(args[index])
        case "--list-sites":
            listSites = true
        case "--no-local":
            forceRemote = true
        case "--dump-sites-response":
            dumpSitesResponse = true
        case "--timeout":
            index += 1
            guard index < args.count, let value = TimeInterval(args[index]) else {
                return .failure("Invalid value for --timeout.")
            }
            timeout = value
        case "--poll-interval":
            index += 1
            guard index < args.count, let value = Int(args[index]) else {
                return .failure("Invalid value for --poll-interval.")
            }
            pollInterval = value
        case "--poll-only-active":
            index += 1
            guard index < args.count, let value = parseBool(args[index]) else {
                return .failure("Invalid value for --poll-only-active.")
            }
            pollOnlyActive = value
        case "--allow-insecure-tls":
            index += 1
            guard index < args.count, let value = parseBool(args[index]) else {
                return .failure("Invalid value for --allow-insecure-tls.")
            }
            allowInsecureTLS = value
        default:
            return .failure("Unknown argument: \(arg)")
        }
        index += 1
    }

    let credentials: TydomConnection.CloudCredentials?
    if let cloudEmail, let cloudPassword {
        credentials = TydomConnection.CloudCredentials(email: cloudEmail, password: cloudPassword)
    } else {
        credentials = nil
    }

    let selectedMode: TydomConnection.Configuration.Mode
    switch mode {
    case "local":
        guard let host else { return .failure("Missing required --host for local mode.") }
        if password == nil && credentials == nil {
            return .failure("Provide --password or --cloud-email and --cloud-password.")
        }
        if mac == nil {
            let options = ResolveOptions(
                mode: mode,
                host: host,
                mac: nil,
                password: password,
                cloudCredentials: credentials,
                siteIndex: siteIndex,
                listSites: listSites,
                timeout: timeout,
                pollInterval: pollInterval,
                pollOnlyActive: pollOnlyActive,
                allowInsecureTLS: allowInsecureTLS,
                dumpSitesResponse: dumpSitesResponse
            )
            return .runResolved(options)
        }
        selectedMode = .local(host: host)
    case "remote":
        if password == nil && credentials == nil {
            return .failure("Provide --password or --cloud-email and --cloud-password.")
        }
        if mac == nil {
            let options = ResolveOptions(
                mode: mode,
                host: host,
                mac: nil,
                password: password,
                cloudCredentials: credentials,
                siteIndex: siteIndex,
                listSites: listSites,
                timeout: timeout,
                pollInterval: pollInterval,
                pollOnlyActive: pollOnlyActive,
                allowInsecureTLS: allowInsecureTLS,
                dumpSitesResponse: dumpSitesResponse
            )
            return .runResolved(options)
        }
        selectedMode = .remote(host: host ?? "mediation.tydom.com")
    case "auto":
        let defaultBonjour = ["_tydom._tcp"]
        let services = bonjourServices.isEmpty ? defaultBonjour : bonjourServices
        let options = AutoOptions(
            mac: mac,
            cloudCredentials: credentials,
            siteIndex: siteIndex,
            bonjourServices: services,
            timeout: timeout,
            pollInterval: pollInterval,
            pollOnlyActive: pollOnlyActive,
            allowInsecureTLS: allowInsecureTLS,
            remoteHost: host,
            listSites: listSites,
            forceRemote: forceRemote,
            dumpSitesResponse: dumpSitesResponse
        )
        return .runAuto(options)
    default:
        return .failure("Invalid --mode value. Use local, remote, or auto.")
    }

    let polling = TydomConnection.Configuration.Polling(
        intervalSeconds: pollInterval,
        onlyWhenActive: pollOnlyActive
    )
    let config = TydomConnection.Configuration(
        mode: selectedMode,
        mac: mac!,
        password: password,
        cloudCredentials: credentials,
        allowInsecureTLS: allowInsecureTLS,
        timeout: timeout,
        polling: polling
    )

    return .run(CLIOptions(configuration: config))
}

private func parseBool(_ value: String) -> Bool? {
    switch value.lowercased() {
    case "true", "1", "yes":
        return true
    case "false", "0", "no":
        return false
    default:
        return nil
    }
}

private func parseInputCommand(_ line: String) -> Result<CLICommand, CLIParseError>? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return nil }

    if trimmed == "help" || trimmed == "?" {
        return .success(.help)
    }
    if trimmed == "quit" || trimmed == "exit" {
        return .success(.quit)
    }
    if trimmed.hasPrefix("raw ") {
        let raw = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
        guard raw.isEmpty == false else {
            return .failure(CLIParseError(message: "raw requires a request string."))
        }
        return .success(.sendRaw(String(raw)))
    }

    let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    guard let command = parts.first?.lowercased() else { return nil }
    let args = Array(parts.dropFirst())

    switch command {
    case "ping":
        return .success(.send(.ping()))
    case "info":
        return .success(.send(.info()))
    case "refresh-all":
        return .success(.send(.refreshAll()))
    case "devices-meta":
        return .success(.send(.devicesMeta()))
    case "devices-data":
        return .success(.send(.devicesData()))
    case "configs-file":
        return .success(.send(.configsFile()))
    case "devices-cmeta":
        return .success(.send(.devicesCmeta()))
    case "areas-meta":
        return .success(.send(.areasMeta()))
    case "areas-cmeta":
        return .success(.send(.areasCmeta()))
    case "areas-data":
        return .success(.send(.areasData()))
    case "moments-file":
        return .success(.send(.momentsFile()))
    case "scenarios-file":
        return .success(.send(.scenariosFile()))
    case "groups-file":
        return .success(.send(.groupsFile()))
    case "api-mode":
        return .success(.send(.apiMode()))
    case "geoloc":
        return .success(.send(.geoloc()))
    case "local-claim":
        return .success(.send(.localClaim()))
    case "update-firmware":
        return .success(.send(.updateFirmware()))
    case "device-data":
        guard args.count == 1 else { return .failure(CLIParseError(message: "device-data <deviceId>")) }
        return .success(.send(.deviceData(deviceId: args[0])))
    case "poll-device":
        guard args.count == 1 else { return .failure(CLIParseError(message: "poll-device <url>")) }
        return .success(.send(.pollDeviceData(url: args[0])))
    case "activate-scenario":
        guard args.count == 1 else { return .failure(CLIParseError(message: "activate-scenario <scenarioId>")) }
        return .success(.send(.activateScenario(args[0])))
    case "set-active":
        guard args.count == 1, let value = parseBool(args[0]) else {
            return .failure(CLIParseError(message: "set-active <true|false>"))
        }
        return .success(.setActive(value))
    case "put-data":
        guard args.count >= 3 else {
            return .failure(CLIParseError(message: "put-data <path> <name> <value> [type]"))
        }
        let value = parsePutDataValue(value: args[2], typeHint: args.count > 3 ? args[3] : nil)
        return .success(.send(.putData(path: args[0], name: args[1], value: value)))
    case "put-devices-data":
        guard args.count >= 4 else {
            return .failure(CLIParseError(message: "put-devices-data <deviceId> <endpointId> <name> <value> [type]"))
        }
        let value = parseDeviceDataValue(value: args[3], typeHint: args.count > 4 ? args[4] : nil)
        return .success(.send(.putDevicesData(
            deviceId: args[0],
            endpointId: args[1],
            name: args[2],
            value: value
        )))
    default:
        return .failure(CLIParseError(message: "Unknown command: \(command). Type `help` for the list."))
    }
}

private func parsePutDataValue(value: String, typeHint: String?) -> TydomCommand.PutDataValue {
    if let typeHint {
        switch typeHint.lowercased() {
        case "null":
            return .null
        case "bool":
            return .bool(parseBool(value) ?? false)
        case "int":
            return .int(Int(value) ?? 0)
        default:
            return .string(value)
        }
    }

    if value.lowercased() == "null" { return .null }
    if let bool = parseBool(value) { return .bool(bool) }
    if let intValue = Int(value) { return .int(intValue) }
    return .string(value)
}

private func parseDeviceDataValue(value: String, typeHint: String?) -> TydomCommand.DeviceDataValue {
    if let typeHint {
        switch typeHint.lowercased() {
        case "null":
            return .null
        case "bool":
            return .bool(parseBool(value) ?? false)
        case "int":
            return .int(Int(value) ?? 0)
        default:
            return .string(value)
        }
    }

    if value.lowercased() == "null" { return .null }
    if let bool = parseBool(value) { return .bool(bool) }
    if let intValue = Int(value) { return .int(intValue) }
    return .string(value)
}

private func helpText() -> String {
    var lines: [String] = []
    lines.append("DeltaDoreCLI")
    lines.append("")
    lines.append("Usage:")
    lines.append("  DeltaDoreCLI --mode local --host <host> --mac <mac> --password <password>")
    lines.append("  DeltaDoreCLI --mode remote --mac <mac> --cloud-email <email> --cloud-password <password>")
    lines.append("  DeltaDoreCLI --mode auto --cloud-email <email> --cloud-password <password> [--site-index <n>]")
    lines.append("")
    lines.append("Options:")
    lines.append("  --mode local|remote|auto      Connection mode (default: local)")
    lines.append("  --host <host>                 Gateway IP or host (required for local)")
    lines.append("  --mac <mac>                   Gateway MAC address (optional with cloud login)")
    lines.append("  --password <password>         Local gateway password")
    lines.append("  --cloud-email <email>         Cloud account email")
    lines.append("  --cloud-password <password>   Cloud account password")
    lines.append("  --site-index <n>              Site index for auto mode (skips prompt)")
    lines.append("  --bonjour-service <type>      Bonjour service type (repeatable)")
    lines.append("  --list-sites                  List available sites and exit (auto mode)")
    lines.append("  --no-local                    Force remote even if local is available (auto mode)")
    lines.append("  --dump-sites-response         Print raw site list response and exit")
    lines.append("  --timeout <seconds>           Request timeout (default: 10)")
    lines.append("  --poll-interval <seconds>     Polling interval (default: 60, 0 disables)")
    lines.append("  --poll-only-active <bool>     Poll only when active (default: true)")
    lines.append("  --allow-insecure-tls <bool>   Allow insecure TLS (default: true)")
    lines.append("  --help                        Show this help")
    lines.append("")
    lines.append("Once connected, type `help` to list interactive commands.")
    return lines.joined(separator: "\n")
}

private func commandHelpText() -> String {
    let entries: [(String, String)] = [
        ("help", "Show available commands"),
        ("quit | exit", "Disconnect and quit"),
        ("set-active <true|false>", "Toggle app activity for polling"),
        ("ping", "GET /ping"),
        ("info", "GET /info"),
        ("refresh-all", "POST /refresh/all"),
        ("devices-meta", "GET /devices/meta"),
        ("devices-data", "GET /devices/data"),
        ("configs-file", "GET /configs/file"),
        ("devices-cmeta", "GET /devices/cmeta"),
        ("areas-meta", "GET /areas/meta"),
        ("areas-cmeta", "GET /areas/cmeta"),
        ("areas-data", "GET /areas/data"),
        ("moments-file", "GET /moments/file"),
        ("scenarios-file", "GET /scenarios/file"),
        ("groups-file", "GET /groups/file"),
        ("api-mode", "PUT /configs/gateway/api_mode"),
        ("geoloc", "GET /configs/gateway/geoloc"),
        ("local-claim", "GET /configs/gateway/local_claim"),
        ("update-firmware", "PUT /configs/gateway/update"),
        ("device-data <deviceId>", "GET /devices/<id>/endpoints/<id>/data"),
        ("poll-device <url>", "GET <url> (used by polling)"),
        ("activate-scenario <scenarioId>", "PUT /scenarios/<id>"),
        ("put-data <path> <name> <value> [type]", "PUT <path> with JSON body"),
        ("put-devices-data <deviceId> <endpointId> <name> <value> [type]", "PUT devices data"),
        ("raw <request>", "Send a raw HTTP request string")
    ]

    var lines: [String] = ["Commands:"]
    for (name, description) in entries {
        lines.append("  \(name) - \(description)")
    }
    return lines.joined(separator: "\n")
}

private func render(message: TydomMessage) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let json = messageToJSONValue(message)
    guard let data = try? encoder.encode(json) else {
        return "{\"error\":\"Failed to encode message\"}"
    }
    return String(data: data, encoding: .utf8) ?? "{\"error\":\"Failed to encode message\"}"
}

private func messageToJSONValue(_ message: TydomMessage) -> JSONValue {
    switch message {
    case .gatewayInfo(let info, let transactionId):
        return .object([
            "type": .string("gatewayInfo"),
            "transactionId": jsonOptionalString(transactionId),
            "payload": .object(info.payload)
        ])
    case .devices(let devices, let transactionId):
        return .object([
            "type": .string("devices"),
            "transactionId": jsonOptionalString(transactionId),
            "payload": .array(devices.map(deviceToJSONValue))
        ])
    case .scenarios(let scenarios, let transactionId):
        return .object([
            "type": .string("scenarios"),
            "transactionId": jsonOptionalString(transactionId),
            "payload": .array(scenarios.map(scenarioToJSONValue))
        ])
    case .groups(let groups, let transactionId):
        return .object([
            "type": .string("groups"),
            "transactionId": jsonOptionalString(transactionId),
            "payload": .array(groups.map(groupToJSONValue))
        ])
    case .moments(let moments, let transactionId):
        return .object([
            "type": .string("moments"),
            "transactionId": jsonOptionalString(transactionId),
            "payload": .array(moments.map(momentToJSONValue))
        ])
    case .areas(let areas, let transactionId):
        return .object([
            "type": .string("areas"),
            "transactionId": jsonOptionalString(transactionId),
            "payload": .array(areas.map(areaToJSONValue))
        ])
    case .raw(let raw):
        return rawMessageToJSONValue(raw)
    }
}

private func deviceToJSONValue(_ device: TydomDevice) -> JSONValue {
    var object: [String: JSONValue] = [
        "id": .number(Double(device.id)),
        "endpointId": .number(Double(device.endpointId)),
        "uniqueId": .string(device.uniqueId),
        "name": .string(device.name),
        "usage": .string(device.usage),
        "kind": .string(deviceKindString(device.kind)),
        "data": .object(device.data)
    ]
    if let metadata = device.metadata {
        object["metadata"] = .object(metadata)
    } else {
        object["metadata"] = .null
    }
    return .object(object)
}

private func scenarioToJSONValue(_ scenario: TydomScenario) -> JSONValue {
    return .object([
        "id": .number(Double(scenario.id)),
        "name": .string(scenario.name),
        "type": .string(scenario.type),
        "picto": .string(scenario.picto),
        "ruleId": jsonOptionalString(scenario.ruleId),
        "payload": .object(scenario.payload)
    ])
}

private func groupToJSONValue(_ group: TydomGroup) -> JSONValue {
    return .object([
        "payload": .object(group.payload)
    ])
}

private func momentToJSONValue(_ moment: TydomMoment) -> JSONValue {
    return .object([
        "payload": .object(moment.payload)
    ])
}

private func areaToJSONValue(_ area: TydomArea) -> JSONValue {
    return .object([
        "id": area.id.map { .number(Double($0)) } ?? .null,
        "payload": .object(area.payload)
    ])
}

private func rawMessageToJSONValue(_ raw: TydomRawMessage) -> JSONValue {
    var object: [String: JSONValue] = [
        "type": .string("raw"),
        "uriOrigin": jsonOptionalString(raw.uriOrigin),
        "transactionId": jsonOptionalString(raw.transactionId),
        "parseError": jsonOptionalString(raw.parseError)
    ]

    let payload = stringForData(raw.payload)
    object["payload"] = .string(payload.value)
    object["payloadEncoding"] = .string(payload.encoding)

    if let frame = raw.frame {
        object["frame"] = httpFrameToJSONValue(frame)
    } else {
        object["frame"] = .null
    }
    return .object(object)
}

private func httpFrameToJSONValue(_ frame: TydomHTTPFrame) -> JSONValue {
    switch frame {
    case .request(let request):
        var object: [String: JSONValue] = [
            "type": .string("request"),
            "method": .string(request.method),
            "path": .string(request.path),
            "headers": jsonObject(from: request.headers)
        ]
        if let body = request.body {
            let payload = stringForData(body)
            object["body"] = .string(payload.value)
            object["bodyEncoding"] = .string(payload.encoding)
        } else {
            object["body"] = .null
        }
        return .object(object)
    case .response(let response):
        var object: [String: JSONValue] = [
            "type": .string("response"),
            "status": .number(Double(response.status)),
            "reason": jsonOptionalString(response.reason),
            "headers": jsonObject(from: response.headers)
        ]
        if let body = response.body {
            let payload = stringForData(body)
            object["body"] = .string(payload.value)
            object["bodyEncoding"] = .string(payload.encoding)
        } else {
            object["body"] = .null
        }
        return .object(object)
    }
}

private func jsonObject(from headers: [String: String]) -> JSONValue {
    let mapped = headers.mapValues { JSONValue.string($0) }
    return .object(mapped)
}

private func jsonOptionalString(_ value: String?) -> JSONValue {
    guard let value else { return .null }
    return .string(value)
}

private func deviceKindString(_ kind: TydomDeviceKind) -> String {
    switch kind {
    case .shutter:
        return "shutter"
    case .window:
        return "window"
    case .door:
        return "door"
    case .garage:
        return "garage"
    case .gate:
        return "gate"
    case .light:
        return "light"
    case .energy:
        return "energy"
    case .smoke:
        return "smoke"
    case .boiler:
        return "boiler"
    case .alarm:
        return "alarm"
    case .weather:
        return "weather"
    case .water:
        return "water"
    case .thermo:
        return "thermo"
    case .other(let raw):
        return raw
    }
}

private func stringForData(_ data: Data) -> (value: String, encoding: String) {
    if let string = String(data: data, encoding: .utf8) {
        return (string, "utf8")
    }
    return (data.base64EncodedString(), "base64")
}
