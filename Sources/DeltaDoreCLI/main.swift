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
        }
    }
}

private enum StartupAction: Sendable {
    case run(CLIOptions)
    case help(String)
    case failure(String)
}

private struct CLIOptions: Sendable {
    let configuration: TydomConnection.Configuration
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
    var timeout: TimeInterval = 10.0
    var pollInterval: Int = 60
    var pollOnlyActive: Bool = true
    var allowInsecureTLS: Bool?

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

    guard let mac else {
        return .failure("Missing required --mac.")
    }

    let credentials: TydomConnection.CloudCredentials?
    if let cloudEmail, let cloudPassword {
        credentials = TydomConnection.CloudCredentials(email: cloudEmail, password: cloudPassword)
    } else {
        credentials = nil
    }

    if password == nil && credentials == nil {
        return .failure("Provide --password or --cloud-email and --cloud-password.")
    }

    let selectedMode: TydomConnection.Configuration.Mode
    switch mode {
    case "local":
        guard let host else { return .failure("Missing required --host for local mode.") }
        selectedMode = .local(host: host)
    case "remote":
        selectedMode = .remote(host: host ?? "mediation.tydom.com")
    default:
        return .failure("Invalid --mode value. Use local or remote.")
    }

    let polling = TydomConnection.Configuration.Polling(
        intervalSeconds: pollInterval,
        onlyWhenActive: pollOnlyActive
    )
    let config = TydomConnection.Configuration(
        mode: selectedMode,
        mac: mac,
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
    lines.append("")
    lines.append("Options:")
    lines.append("  --mode local|remote           Connection mode (default: local)")
    lines.append("  --host <host>                 Gateway IP or host (required for local)")
    lines.append("  --mac <mac>                   Gateway MAC address (required)")
    lines.append("  --password <password>         Local gateway password")
    lines.append("  --cloud-email <email>         Cloud account email")
    lines.append("  --cloud-password <password>   Cloud account password")
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
