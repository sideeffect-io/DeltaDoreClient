import Foundation

/// WebSocket connection to a Tydom gateway using HTTP Digest authentication.
///
/// Example:
/// ```swift
/// let config = TydomConnection.Configuration(
///     mode: .local(host: "192.168.1.50"),
///     mac: "AA:BB:CC:DD:EE:FF",
///     password: "gateway-password"
/// )
/// let connection = TydomConnection(configuration: config)
/// try await connection.connect()
///
/// Task {
///     for await data in await connection.messages() {
///         // Handle incoming HTTP-over-WS frames.
///     }
/// }
///
/// let request = "GET /ping HTTP/1.1\r\n\r\n"
/// try await connection.send(Data(request.utf8))
/// ```
public actor TydomConnection {
    let configuration: Configuration
    private let dependencies: Dependencies
    private let log: @Sendable (String) -> Void

    private var session: URLSession?
    private var socketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?

    private let messageStream: AsyncStream<Data>
    private var messageContinuation: AsyncStream<Data>.Continuation?
    private let activityStore = TydomAppActivityStore()

    public init(
        configuration: Configuration,
        log: @escaping @Sendable (String) -> Void = { _ in },
        onDisconnect: (@Sendable () async -> Void)? = nil
    ) {
        let dependencies = Dependencies.live(onDisconnect: onDisconnect ?? {})
        self.init(configuration: configuration, dependencies: dependencies, log: log)
    }

    init(
        configuration: Configuration,
        dependencies: Dependencies,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.dependencies = dependencies
        self.log = log

        let streamResult = AsyncStream<Data>.makeStream()
        self.messageStream = streamResult.stream
        self.messageContinuation = streamResult.continuation
    }

    deinit {
        receiveTask?.cancel()
        keepAliveTask?.cancel()
        socketTask?.cancel(with: .goingAway, reason: nil)
        if let session {
            dependencies.invalidateSession(session)
        }
    }

    public func messages() -> AsyncStream<Data> {
        messageStream
    }

    public func setAppActive(_ isActive: Bool) async {
        await activityStore.setActive(isActive)
    }

    func isAppActive() async -> Bool {
        await activityStore.isAppActive()
    }

    public func connect() async throws {
        guard socketTask == nil else { return }

        log("Connecting to \(configuration.webSocketURL.absoluteString)")

        let passwordSession = dependencies.makeSession(
            configuration.allowInsecureTLS,
            configuration.timeout,
            nil
        )
        let password = try await resolvePassword(using: passwordSession)
        dependencies.invalidateSession(passwordSession)

        let credential = URLCredential(
            user: configuration.digestUsername,
            password: password,
            persistence: .forSession
        )
        let session = dependencies.makeSession(
            configuration.allowInsecureTLS,
            configuration.timeout,
            credential
        )
        self.session = session

        var request = URLRequest(url: configuration.webSocketURL)
        request.timeoutInterval = configuration.timeout

        let task = session.webSocketTask(with: request)
        task.resume()

        self.socketTask = task
        log("WebSocket task resumed.")
        startReceiving(from: task)
        startKeepAlive()
    }

    public func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        keepAliveTask?.cancel()
        keepAliveTask = nil

        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil

        if let session {
            dependencies.invalidateSession(session)
        }
        session = nil
        log("Disconnected.")
        Task { await dependencies.onDisconnect() }
    }

    public func send(_ data: Data) async throws {
        guard let task = socketTask else {
            log("Send failed: not connected.")
            throw ConnectionError.notConnected
        }
        let payload = applyOutgoingPrefix(to: data)
        try await task.send(.data(payload))
    }

    public func send(text: String) async throws {
        guard let task = socketTask else {
            log("Send failed: not connected.")
            throw ConnectionError.notConnected
        }
        let payload = applyOutgoingPrefix(to: Data(text.utf8))
        try await task.send(.data(payload))
    }

    private func startReceiving(from task: URLSessionWebSocketTask) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    switch message {
                    case .data(let data):
                        await self.handleIncoming(data)
                    case .string(let string):
                        await self.handleIncoming(Data(string.utf8))
                    @unknown default:
                        break
                    }
                } catch {
                    if Task.isCancelled { break }
                    let closeCode = task.closeCode.rawValue
                    let reason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? "n/a"
                    log("WebSocket receive failed: \(error) (closeCode=\(closeCode), reason=\(reason))")
                    await self.handleReceiveFailure(task: task)
                    break
                }
            }
        }
    }

    private func startKeepAlive() {
        keepAliveTask?.cancel()
        let config = configuration.keepAlive
        guard config.isEnabled else { return }
        keepAliveTask = Task { [weak self] in
            guard let self else { return }
            let sleepNanoseconds = UInt64(config.intervalSeconds) * 1_000_000_000
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: sleepNanoseconds)
                } catch {
                    break
                }
                if config.onlyWhenActive {
                    let isActive = await self.isAppActive()
                    guard isActive else { continue }
                }
                _ = try? await self.send(TydomCommand.ping())
            }
        }
    }

    private func handleReceiveFailure(task: URLSessionWebSocketTask) {
        if socketTask === task {
            socketTask = nil
        }
    }

    private func handleIncoming(_ data: Data) {
        let cleaned = stripIncomingPrefix(from: data)
        messageContinuation?.yield(cleaned)
    }

    private func resolvePassword(using session: URLSession) async throws -> String {
        if let password = configuration.password {
            return password
        }
        guard let credentials = configuration.cloudCredentials else {
            throw ConnectionError.missingCredentials
        }
        return try await dependencies.fetchGatewayPassword(credentials, configuration.mac, session)
    }

    private func fetchDigestChallenge(
        using session: URLSession,
        randomBytes: @Sendable (Int) -> [UInt8]
    ) async throws -> DigestChallenge {
        do {
            return try await fetchDigestChallenge(
                using: session,
                randomBytes: randomBytes,
                includeUpgradeHeaders: true
            )
        } catch {
            if shouldRetryDigestChallenge(error: error) {
                return try await fetchDigestChallenge(
                    using: session,
                    randomBytes: randomBytes,
                    includeUpgradeHeaders: false
                )
            }
            throw error
        }
    }

    private func fetchDigestChallenge(
        using session: URLSession,
        randomBytes: @Sendable (Int) -> [UInt8],
        includeUpgradeHeaders: Bool
    ) async throws -> DigestChallenge {
        var request = URLRequest(url: configuration.httpsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = configuration.timeout
        let handshakeHeaders = buildHandshakeHeaders(
            randomBytes: randomBytes,
            includeUpgradeHeaders: includeUpgradeHeaders
        )
        for (key, value) in handshakeHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.invalidResponse
        }
        let rawHeader = httpResponse.allHeaderFields.first { key, _ in
            String(describing: key).lowercased() == "www-authenticate"
        }?.value as? String
        guard let rawHeader else { throw ConnectionError.missingChallenge }
        return try DigestChallenge.parse(from: rawHeader)
    }

    private func buildHandshakeHeaders(
        randomBytes: @Sendable (Int) -> [UInt8],
        includeUpgradeHeaders: Bool
    ) -> [String: String] {
        var headers: [String: String] = [
            "Host": "\(configuration.host):443",
            "Accept": "*/*"
        ]
        guard includeUpgradeHeaders else { return headers }
        let key = Data(randomBytes(16)).base64EncodedString()
        headers["Connection"] = "Upgrade"
        headers["Upgrade"] = "websocket"
        headers["Sec-WebSocket-Key"] = key
        headers["Sec-WebSocket-Version"] = "13"
        return headers
    }

    private func shouldRetryDigestChallenge(error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.code == .networkConnectionLost
        }
        return false
    }

    private func applyOutgoingPrefix(to data: Data) -> Data {
        guard let prefix = configuration.commandPrefix else { return data }
        var output = Data([prefix])
        output.append(data)
        return output
    }

    private func stripIncomingPrefix(from data: Data) -> Data {
        guard let prefix = configuration.commandPrefix else { return data }
        guard data.first == prefix else { return data }
        return Data(data.dropFirst())
    }

    private func buildDigestAuthorization(
        challenge: DigestChallenge,
        username: String,
        password: String,
        method: String,
        uri: String,
        randomBytes: @Sendable (Int) -> [UInt8]
    ) throws -> String {
        try DigestAuthorizationBuilder.build(
            challenge: challenge,
            username: username,
            password: password,
            method: method,
            uri: uri,
            randomBytes: randomBytes
        )
    }
}

private extension URL {
    var requestTarget: String {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return path
        }
        components.scheme = nil
        components.host = nil
        components.port = nil
        return components.string ?? path
    }
}
