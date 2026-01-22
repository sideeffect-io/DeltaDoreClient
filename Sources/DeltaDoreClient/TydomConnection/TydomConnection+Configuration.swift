import Foundation

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public extension TydomConnection {
    struct Configuration: Sendable {
        enum Mode: Sendable {
            case local(host: String)
            case remote(host: String = "mediation.tydom.com")
        }

        let mode: Mode
        let mac: String
        let password: String?
        let cloudCredentials: CloudCredentials?
        let allowInsecureTLS: Bool
        let timeout: TimeInterval

        init(
            mode: Mode,
            mac: String,
            password: String? = nil,
            cloudCredentials: CloudCredentials? = nil,
            allowInsecureTLS: Bool? = nil,
            timeout: TimeInterval = 10.0
        ) {
            self.mode = mode
            self.mac = mac
            self.password = password
            self.cloudCredentials = cloudCredentials
            self.allowInsecureTLS = allowInsecureTLS ?? true
            self.timeout = timeout
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
                URLQueryItem(name: "mac", value: mac),
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
                URLQueryItem(name: "mac", value: mac),
                URLQueryItem(name: "appli", value: "1")
            ]
            return components.url!
        }
    }
}
