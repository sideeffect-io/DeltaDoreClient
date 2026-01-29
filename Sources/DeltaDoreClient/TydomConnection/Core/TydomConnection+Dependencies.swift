import Foundation

extension TydomConnection {
    struct Dependencies: Sendable {
        var makeSession: @Sendable (_ allowInsecureTLS: Bool, _ timeout: TimeInterval, _ credential: URLCredential?) -> URLSession
        var randomBytes: @Sendable (_ count: Int) -> [UInt8]
        var now: @Sendable () -> Date
        var fetchGatewayPassword: @Sendable (_ credentials: CloudCredentials, _ mac: String, _ session: URLSession) async throws -> String
        var invalidateSession: @Sendable (_ session: URLSession) -> Void
        var onDisconnect: @Sendable () async -> Void

        init(
            makeSession: @Sendable @escaping (_ allowInsecureTLS: Bool, _ timeout: TimeInterval, _ credential: URLCredential?) -> URLSession,
            randomBytes: @Sendable @escaping (_ count: Int) -> [UInt8],
            now: @Sendable @escaping () -> Date,
            fetchGatewayPassword: @Sendable @escaping (_ credentials: CloudCredentials, _ mac: String, _ session: URLSession) async throws -> String,
            invalidateSession: @Sendable @escaping (_ session: URLSession) -> Void = { $0.invalidateAndCancel() },
            onDisconnect: @Sendable @escaping () async -> Void = {}
        ) {
            self.makeSession = makeSession
            self.randomBytes = randomBytes
            self.now = now
            self.fetchGatewayPassword = fetchGatewayPassword
            self.invalidateSession = invalidateSession
            self.onDisconnect = onDisconnect
        }

        static func live(onDisconnect: @escaping @Sendable () async -> Void = {}) -> Dependencies {
            Dependencies(
                makeSession: { allowInsecureTLS, timeout, credential in
                    let configuration = URLSessionConfiguration.default
                    configuration.timeoutIntervalForRequest = timeout
                    configuration.timeoutIntervalForResource = timeout
                    let delegate = InsecureTLSDelegate(
                        allowInsecureTLS: allowInsecureTLS,
                        credential: credential
                    )
                    return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
                },
                randomBytes: { count in
                    (0..<count).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
                },
                now: { Date() },
                fetchGatewayPassword: { credentials, mac, session in
                    try await TydomCloudPasswordProvider.fetchGatewayPassword(
                        email: credentials.email,
                        password: credentials.password,
                        mac: mac,
                        session: session
                    )
                },
                invalidateSession: { session in
                    session.invalidateAndCancel()
                },
                onDisconnect: onDisconnect
            )
        }
    }
}
