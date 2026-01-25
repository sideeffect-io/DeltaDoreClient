import Foundation

extension TydomConnection {
    public struct Configuration: Sendable {
        public struct Polling: Sendable {
            public let intervalSeconds: Int
            public let onlyWhenActive: Bool

            public init(intervalSeconds: Int = 60, onlyWhenActive: Bool = true) {
                self.intervalSeconds = intervalSeconds
                self.onlyWhenActive = onlyWhenActive
            }

            public var isEnabled: Bool {
                intervalSeconds > 0
            }
        }

        public struct KeepAlive: Sendable {
            public let intervalSeconds: Int
            public let onlyWhenActive: Bool

            public init(intervalSeconds: Int = 30, onlyWhenActive: Bool = true) {
                self.intervalSeconds = intervalSeconds
                self.onlyWhenActive = onlyWhenActive
            }

            public var isEnabled: Bool {
                intervalSeconds > 0
            }
        }

        public enum Mode: Sendable {
            case local(host: String)
            case remote(host: String = "mediation.tydom.com")
        }

        public let mode: Mode
        public let mac: String
        public let password: String?
        public let cloudCredentials: CloudCredentials?
        public let allowInsecureTLS: Bool
        public let timeout: TimeInterval
        public let polling: Polling
        public let keepAlive: KeepAlive

        public init(
            mode: Mode,
            mac: String,
            password: String? = nil,
            cloudCredentials: CloudCredentials? = nil,
            allowInsecureTLS: Bool? = nil,
            timeout: TimeInterval = 10.0,
            polling: Polling = Polling(),
            keepAlive: KeepAlive = KeepAlive()
        ) {
            self.mode = mode
            self.mac = mac
            self.password = password
            self.cloudCredentials = cloudCredentials
            self.allowInsecureTLS = allowInsecureTLS ?? true
            self.timeout = timeout
            self.polling = polling
            self.keepAlive = keepAlive
        }

        var normalizedMac: String {
            mac.filter { $0.isHexDigit }.uppercased()
        }

        var digestUsername: String {
            return isRemote ? normalizedMac : mac
        }

        var queryMac: String {
            return isRemote ? normalizedMac : mac
        }

        var host: String {
            switch mode {
            case .local(let host):
                return host
            case .remote(let host):
                return host
            }
        }

        var isRemote: Bool {
            if case .remote = mode { return true }
            return false
        }

        var commandPrefix: UInt8? {
            return isRemote ? 0x02 : nil
        }

        var webSocketURL: URL {
            var components = URLComponents()
            components.scheme = "wss"
            components.host = host
            components.port = 443
            components.path = "/mediation/client"
            components.queryItems = [
                URLQueryItem(name: "mac", value: queryMac),
                URLQueryItem(name: "appli", value: "1")
            ]
            return components.url!
        }

        var httpsURL: URL {
            var components = URLComponents()
            components.scheme = "https"
            components.host = host
            components.port = 443
            components.path = "/mediation/client"
            components.queryItems = [
                URLQueryItem(name: "mac", value: queryMac),
                URLQueryItem(name: "appli", value: "1")
            ]
            return components.url!
        }
    }
}
