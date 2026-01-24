import Foundation

extension TydomConnection {
    struct Dependencies: Sendable {
        var makeSession: @Sendable (_ allowInsecureTLS: Bool, _ timeout: TimeInterval) -> URLSession
        var randomBytes: @Sendable (_ count: Int) -> [UInt8]
        var now: @Sendable () -> Date
        var fetchGatewayPassword: @Sendable (_ credentials: CloudCredentials, _ mac: String, _ session: URLSession) async throws -> String
        var invalidateSession: @Sendable (_ session: URLSession) -> Void

        init(
            makeSession: @Sendable @escaping (_ allowInsecureTLS: Bool, _ timeout: TimeInterval) -> URLSession,
            randomBytes: @Sendable @escaping (_ count: Int) -> [UInt8],
            now: @Sendable @escaping () -> Date,
            fetchGatewayPassword: @Sendable @escaping (_ credentials: CloudCredentials, _ mac: String, _ session: URLSession) async throws -> String,
            invalidateSession: @Sendable @escaping (_ session: URLSession) -> Void = { $0.invalidateAndCancel() }
        ) {
            self.makeSession = makeSession
            self.randomBytes = randomBytes
            self.now = now
            self.fetchGatewayPassword = fetchGatewayPassword
            self.invalidateSession = invalidateSession
        }

        static func live() -> Dependencies {
            Dependencies(
                makeSession: { allowInsecureTLS, timeout in
                    let configuration = URLSessionConfiguration.default
                    configuration.timeoutIntervalForRequest = timeout
                    configuration.timeoutIntervalForResource = timeout
                    let delegate = InsecureTLSDelegate(allowInsecureTLS: allowInsecureTLS)
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
                }
            )
        }
    }
}
