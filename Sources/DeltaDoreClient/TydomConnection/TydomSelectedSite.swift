import Foundation

public struct TydomSelectedSite: Sendable, Equatable {
    public let id: String
    public let name: String
    public let gatewayMac: String

    public init(id: String, name: String, gatewayMac: String) {
        self.id = id
        self.name = name
        self.gatewayMac = TydomMac.normalize(gatewayMac)
    }
}
