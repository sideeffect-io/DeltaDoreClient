import Foundation

struct TydomDecodedEnvelope: Sendable, Equatable {
    let raw: TydomRawMessage
    let payload: TydomDecodedPayload
    let cacheMutations: [TydomCacheMutation]
    let effects: [TydomMessageEffect]

    init(
        raw: TydomRawMessage,
        payload: TydomDecodedPayload,
        cacheMutations: [TydomCacheMutation] = [],
        effects: [TydomMessageEffect] = []
    ) {
        self.raw = raw
        self.payload = payload
        self.cacheMutations = cacheMutations
        self.effects = effects
    }
}

enum TydomDecodedPayload: Sendable, Equatable {
    case gatewayInfo(TydomGatewayInfo)
    case deviceUpdates([TydomDeviceUpdate])
    case scenarios([TydomScenarioPayload])
    case groups([TydomGroup])
    case moments([TydomMoment])
    case areas([TydomArea])
    case none
}

enum TydomCacheMutation: Sendable, Equatable {
    case deviceEntry(TydomDeviceCacheEntry)
    case scenarioMetadata(TydomScenarioMetadata)
}

struct TydomScenarioMetadata: Sendable, Equatable {
    let id: Int
    let name: String
    let type: String
    let picto: String
    let ruleId: String?

    init(
        id: Int,
        name: String,
        type: String,
        picto: String,
        ruleId: String?
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.picto = picto
        self.ruleId = ruleId
    }
}

struct TydomScenarioPayload: Sendable, Equatable {
    let id: Int
    let payload: [String: JSONValue]

    init(id: Int, payload: [String: JSONValue]) {
        self.id = id
        self.payload = payload
    }
}

struct TydomDeviceUpdate: Sendable, Equatable {
    enum Source: Sendable, Equatable {
        case data
        case cdata
    }

    let id: Int
    let endpointId: Int
    let uniqueId: String
    let data: [String: JSONValue]
    let metadata: [String: JSONValue]?
    let cdataEntries: [JSONValue]?
    let source: Source

    init(
        id: Int,
        endpointId: Int,
        uniqueId: String,
        data: [String: JSONValue],
        metadata: [String: JSONValue]? = nil,
        cdataEntries: [JSONValue]? = nil,
        source: Source
    ) {
        self.id = id
        self.endpointId = endpointId
        self.uniqueId = uniqueId
        self.data = data
        self.metadata = metadata
        self.cdataEntries = cdataEntries
        self.source = source
    }
}
