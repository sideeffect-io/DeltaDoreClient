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
    let client = makeClient()
    if await handleSiteListingIfNeeded(
        listSites: options.listSites,
        dumpSitesResponse: options.dumpSitesResponse,
        cloudCredentials: options.cloudCredentials,
        client: client,
        stdout: stdout,
        stderr: stderr
    ) {
        return nil
    }

    let polling = TydomConnection.Configuration.Polling(
        intervalSeconds: options.pollInterval,
        onlyWhenActive: options.pollOnlyActive
    )
    let resolverOptions = DeltaDoreClient.Options(
        mode: .auto,
        remoteHostOverride: options.remoteHost,
        mac: options.mac,
        cloudCredentials: options.cloudCredentials,
        siteIndex: options.siteIndex,
        resetSelectedSite: options.resetSite,
        selectedSiteAccount: "default",
        allowInsecureTLS: options.allowInsecureTLS,
        timeout: options.timeout,
        polling: polling,
        bonjourServices: options.bonjourServices,
        forceRemote: options.forceRemote
    )

    do {
        let resolution = try await client.resolve(
            options: resolverOptions,
            selectSiteIndex: { sites in
                await chooseSiteIndex(sites, stdout: stdout, stderr: stderr)
            }
        )
        return CLIOptions(
            configuration: resolution.configuration,
            onDisconnect: resolution.onDisconnect
        )
    } catch {
        await stderr.writeLine("Failed to resolve connection: \(error.localizedDescription)")
        return nil
    }
}

func resolveExplicitConfiguration(
    options: ResolveOptions,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) async -> CLIOptions? {
    let client = makeClient()
    if await handleSiteListingIfNeeded(
        listSites: options.listSites,
        dumpSitesResponse: options.dumpSitesResponse,
        cloudCredentials: options.cloudCredentials,
        client: client,
        stdout: stdout,
        stderr: stderr
    ) {
        return nil
    }

    let mode: DeltaDoreClient.Options.Mode = options.mode == "remote" ? .remote : .local
    let polling = TydomConnection.Configuration.Polling(
        intervalSeconds: options.pollInterval,
        onlyWhenActive: options.pollOnlyActive
    )
    let resolverOptions = DeltaDoreClient.Options(
        mode: mode,
        localHostOverride: options.mode == "local" ? options.host : nil,
        remoteHostOverride: options.mode == "remote" ? options.host : nil,
        mac: options.mac,
        password: options.password,
        cloudCredentials: options.cloudCredentials,
        siteIndex: options.siteIndex,
        resetSelectedSite: options.resetSite,
        selectedSiteAccount: "default",
        allowInsecureTLS: options.allowInsecureTLS,
        timeout: options.timeout,
        polling: polling,
        bonjourServices: options.bonjourServices,
        onDecision: { decision in
            await stderr.writeLine("Decision: \(decision.reason.rawValue) -> \(decision.mode)")
        }
    )

    do {
        let resolution = try await client.resolve(
            options: resolverOptions,
            selectSiteIndex: { sites in
                await chooseSiteIndex(sites, stdout: stdout, stderr: stderr)
            }
        )
        return CLIOptions(
            configuration: resolution.configuration,
            onDisconnect: resolution.onDisconnect
        )
    } catch {
        await stderr.writeLine("Failed to resolve connection: \(error.localizedDescription)")
        return nil
    }
}

private func makeClient() -> DeltaDoreClient {
    DeltaDoreClient.live(
        credentialService: "io.sideeffect.deltadoreclient.cli",
        selectedSiteService: "io.sideeffect.deltadoreclient.cli.site-selection"
    )
}

private func handleSiteListingIfNeeded(
    listSites: Bool,
    dumpSitesResponse: Bool,
    cloudCredentials: TydomConnection.CloudCredentials?,
    client: DeltaDoreClient,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) async -> Bool {
    if dumpSitesResponse {
        guard let cloudCredentials else {
            await stderr.writeLine("Missing cloud credentials to fetch sites.")
            return true
        }
        do {
            let payload = try await client.listSitesPayload(cloudCredentials: cloudCredentials)
            let output = String(data: payload, encoding: .utf8) ?? "<non-utf8>"
            await stdout.writeLine(output)
        } catch {
            await stderr.writeLine("Failed to fetch sites: \(error.localizedDescription)")
        }
        return true
    }

    if listSites {
        guard let cloudCredentials else {
            await stderr.writeLine("Missing cloud credentials to list sites.")
            return true
        }
        do {
            let sites = try await client.listSites(cloudCredentials: cloudCredentials)
            await printSites(sites, stdout: stdout)
        } catch {
            await stderr.writeLine("Failed to fetch sites: \(error.localizedDescription)")
        }
        return true
    }

    return false
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
