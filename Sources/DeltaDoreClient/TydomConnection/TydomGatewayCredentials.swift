import Foundation

public struct TydomGatewayCredentials: Sendable, Equatable {
    public let mac: String
    public let password: String
    public let cachedLocalIP: String?
    public let updatedAt: Date

    public init(mac: String, password: String, cachedLocalIP: String?, updatedAt: Date) {
        self.mac = TydomMac.normalize(mac)
        self.password = password
        self.cachedLocalIP = cachedLocalIP
        self.updatedAt = updatedAt
    }
}
