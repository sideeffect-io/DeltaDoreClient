import Foundation

public enum TydomMessage: Sendable, Equatable {
    case gatewayInfo(TydomGatewayInfo, transactionId: String?)
    case devices([TydomDevice], transactionId: String?)
    case raw(TydomRawMessage)
}

public struct TydomRawMessage: Sendable, Equatable {
    public let payload: Data
    public let frame: TydomHTTPFrame?
    public let uriOrigin: String?
    public let transactionId: String?
    public let parseError: String?

    public init(
        payload: Data,
        frame: TydomHTTPFrame?,
        uriOrigin: String?,
        transactionId: String?,
        parseError: String?
    ) {
        self.payload = payload
        self.frame = frame
        self.uriOrigin = uriOrigin
        self.transactionId = transactionId
        self.parseError = parseError
    }
}

public struct TydomGatewayInfo: Sendable, Equatable {
    public let payload: [String: JSONValue]

    public init(payload: [String: JSONValue]) {
        self.payload = payload
    }
}

public struct TydomDeviceInfo: Sendable, Equatable {
    public let name: String
    public let usage: String
    public let metadata: [String: JSONValue]?

    public init(name: String, usage: String, metadata: [String: JSONValue]? = nil) {
        self.name = name
        self.usage = usage
        self.metadata = metadata
    }
}


public struct TydomDevice: Sendable, Equatable {
    public let id: Int
    public let endpointId: Int
    public let uniqueId: String
    public let name: String
    public let usage: String
    public let kind: TydomDeviceKind
    public let data: [String: JSONValue]
    public let metadata: [String: JSONValue]?

    public init(
        id: Int,
        endpointId: Int,
        uniqueId: String,
        name: String,
        usage: String,
        kind: TydomDeviceKind,
        data: [String: JSONValue],
        metadata: [String: JSONValue]?
    ) {
        self.id = id
        self.endpointId = endpointId
        self.uniqueId = uniqueId
        self.name = name
        self.usage = usage
        self.kind = kind
        self.data = data
        self.metadata = metadata
    }
}

public enum TydomDeviceKind: Sendable, Equatable {
    case shutter
    case window
    case door
    case garage
    case gate
    case light
    case energy
    case smoke
    case boiler
    case alarm
    case weather
    case water
    case thermo
    case other(String)

    public static func fromUsage(_ usage: String) -> TydomDeviceKind {
        switch usage {
        case "shutter", "klineShutter", "awning", "swingShutter":
            return .shutter
        case "window", "windowFrench", "windowSliding", "klineWindowFrench", "klineWindowSliding":
            return .window
        case "belmDoor", "klineDoor":
            return .door
        case "garage_door":
            return .garage
        case "gate":
            return .gate
        case "light":
            return .light
        case "conso":
            return .energy
        case "sensorDFR":
            return .smoke
        case "boiler", "sh_hvac", "electric", "aeraulic":
            return .boiler
        case "alarm":
            return .alarm
        case "weather":
            return .weather
        case "sensorDF":
            return .water
        case "sensorThermo":
            return .thermo
        default:
            return .other(usage)
        }
    }
}
