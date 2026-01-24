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

    private var session: URLSession?
    private var socketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?

    private let messageStream: AsyncStream<Data>
    private var messageContinuation: AsyncStream<Data>.Continuation?
    private let activityStore = TydomAppActivityStore()

    public init(configuration: Configuration) {
        self.init(configuration: configuration, dependencies: .live())
    }

    init(configuration: Configuration, dependencies: Dependencies = .live()) {
        self.configuration = configuration
        self.dependencies = dependencies

        let streamResult = AsyncStream<Data>.makeStream()
        self.messageStream = streamResult.stream
        self.messageContinuation = streamResult.continuation
    }

    deinit {
        receiveTask?.cancel()
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

        let session = dependencies.makeSession(configuration.allowInsecureTLS, configuration.timeout)
        self.session = session

        let password = try await resolvePassword(using: session)
        let challenge = try await fetchDigestChallenge(using: session, randomBytes: dependencies.randomBytes)
        let authorization = try buildDigestAuthorization(
            challenge: challenge,
            username: configuration.mac,
            password: password,
            method: "GET",
            uri: configuration.webSocketURL.requestTarget,
            randomBytes: dependencies.randomBytes
        )

        var request = URLRequest(url: configuration.webSocketURL)
        request.timeoutInterval = configuration.timeout
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        task.resume()

        self.socketTask = task
        startReceiving(from: task)
    }

    public func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil

        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil

        if let session {
            dependencies.invalidateSession(session)
        }
        session = nil
    }

    public func send(_ data: Data) async throws {
        guard let task = socketTask else { throw ConnectionError.notConnected }
        let payload = applyOutgoingPrefix(to: data)
        try await task.send(.data(payload))
    }

    public func send(text: String) async throws {
        guard let task = socketTask else { throw ConnectionError.notConnected }
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
                    await self.handleReceiveFailure(task: task)
                    break
                }
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
        var request = URLRequest(url: configuration.httpsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = configuration.timeout
        let handshakeHeaders = buildHandshakeHeaders(randomBytes: randomBytes)
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

    private func buildHandshakeHeaders(randomBytes: @Sendable (Int) -> [UInt8]) -> [String: String] {
        let key = Data(randomBytes(16)).base64EncodedString()
        return [
            "Connection": "Upgrade",
            "Upgrade": "websocket",
            "Host": "\(configuration.host):443",
            "Accept": "*/*",
            "Sec-WebSocket-Key": key,
            "Sec-WebSocket-Version": "13"
        ]
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
