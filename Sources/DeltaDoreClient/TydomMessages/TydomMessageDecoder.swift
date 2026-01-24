import Foundation

struct TydomDeviceCacheEntry: Sendable, Equatable {
    let uniqueId: String
    var name: String?
    var usage: String?
    var metadata: [String: JSONValue]?

    init(
        uniqueId: String,
        name: String? = nil,
        usage: String? = nil,
        metadata: [String: JSONValue]? = nil
    ) {
        self.uniqueId = uniqueId
        self.name = name
        self.usage = usage
        self.metadata = metadata
    }
}

enum TydomMessageDecoder {
    static func decode(_ raw: TydomRawMessage) -> TydomDecodedEnvelope {
        guard raw.parseError == nil else {
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }
        guard let frame = raw.frame, let body = frame.body, body.isEmpty == false else {
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        let uriOrigin = raw.uriOrigin

        if uriOrigin == "/info" {
            if let info = decodeGatewayInfo(body) {
                return TydomDecodedEnvelope(raw: raw, payload: .gatewayInfo(info))
            }
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        if uriOrigin == "/configs/file" {
            if let mutations = decodeConfigsFile(body) {
                return TydomDecodedEnvelope(raw: raw, payload: .none, cacheMutations: mutations)
            }
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        if uriOrigin == "/devices/meta" {
            if let mutations = decodeDevicesMeta(body) {
                return TydomDecodedEnvelope(raw: raw, payload: .none, cacheMutations: mutations)
            }
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        if uriOrigin == "/devices/cmeta" || uriOrigin == "/areas/cmeta" {
            if let result = decodeDevicesCMeta(body), result.urls.isEmpty == false || result.mutations.isEmpty == false {
                return TydomDecodedEnvelope(
                    raw: raw,
                    payload: .none,
                    cacheMutations: result.mutations,
                    effects: result.urls.isEmpty ? [] : [.schedulePoll(urls: result.urls, intervalSeconds: 60)]
                )
            }
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        if isDevicesData(uriOrigin) {
            if let updates = decodeDevicesData(body) {
                return TydomDecodedEnvelope(raw: raw, payload: .deviceUpdates(updates))
            }
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        if isDevicesCData(uriOrigin) {
            if let updates = decodeDevicesCData(body) {
                return TydomDecodedEnvelope(raw: raw, payload: .deviceUpdates(updates))
            }
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        if uriOrigin == "/events" {
            return TydomDecodedEnvelope(raw: raw, payload: .none, effects: [.refreshAll])
        }

        if uriOrigin == "/ping" {
            return TydomDecodedEnvelope(raw: raw, payload: .none, effects: [.pongReceived])
        }

        if uriOrigin == "/groups/file" {
            if let groups = decodeGroupsFile(body) {
                return TydomDecodedEnvelope(raw: raw, payload: .groups(groups))
            }
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        if uriOrigin == "/areas/data" {
            if let areas = decodeAreasData(body) {
                return TydomDecodedEnvelope(raw: raw, payload: .areas(areas))
            }
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        if uriOrigin == "/moments/file" {
            if let moments = decodeMomentsFile(body) {
                return TydomDecodedEnvelope(raw: raw, payload: .moments(moments))
            }
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        if uriOrigin == "/scenarios/file" {
            if let scenarios = decodeScenariosFile(body) {
                return TydomDecodedEnvelope(raw: raw, payload: .scenarios(scenarios))
            }
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        return TydomDecodedEnvelope(raw: raw, payload: .none)
    }

    private static func decodeGatewayInfo(_ data: Data) -> TydomGatewayInfo? {
        guard let payload = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
            return nil
        }
        return TydomGatewayInfo(payload: payload)
    }

    private static func decodeDevicesData(_ data: Data) -> [TydomDeviceUpdate]? {
        guard let payload = decodePayloadArray(DevicesDataPayload.self, from: data) else { return nil }

        var updates: [TydomDeviceUpdate] = []
        for device in payload {
            for endpoint in device.endpoints {
                let uniqueId = "\(endpoint.id)_\(device.id)"
                let values = extractDataValues(from: endpoint)
                updates.append(TydomDeviceUpdate(
                    id: device.id,
                    endpointId: endpoint.id,
                    uniqueId: uniqueId,
                    data: values,
                    metadata: nil,
                    cdataEntries: nil,
                    source: .data
                ))
            }
        }
        return updates
    }

    private static func extractDataValues(from endpoint: DevicesDataPayload.Endpoint) -> [String: JSONValue] {
        guard endpoint.error == nil || endpoint.error == 0 else { return [:] }
        guard let entries = endpoint.data else { return [:] }
        var values: [String: JSONValue] = [:]
        for entry in entries {
            guard entry.validity == "upToDate", let value = entry.value else { continue }
            values[entry.name] = value
        }
        return values
    }

    private static func decodeDevicesCData(_ data: Data) -> [TydomDeviceUpdate]? {
        guard let payload = decodePayloadArray(DevicesCDataPayload.self, from: data) else { return nil }

        var updates: [TydomDeviceUpdate] = []
        for device in payload {
            for endpoint in device.endpoints {
                guard endpoint.error == nil || endpoint.error == 0 else { continue }
                let uniqueId = "\(endpoint.id)_\(device.id)"
                let values = extractCDataValues(from: endpoint)
                let entries = endpoint.cdata ?? []
                let entryPayloads = entries.map { JSONValue.object($0.payload) }
                guard entryPayloads.isEmpty == false || values.isEmpty == false else { continue }

                updates.append(TydomDeviceUpdate(
                    id: device.id,
                    endpointId: endpoint.id,
                    uniqueId: uniqueId,
                    data: values,
                    metadata: nil,
                    cdataEntries: entryPayloads.isEmpty ? nil : entryPayloads,
                    source: .cdata
                ))
            }
        }
        return updates
    }

    private static func extractCDataValues(from endpoint: DevicesCDataPayload.Endpoint) -> [String: JSONValue] {
        guard let entries = endpoint.cdata else { return [:] }
        var values: [String: JSONValue] = [:]
        for entry in entries {
            if let dest = entry.parameters?["dest"]?.stringValue,
               let counter = entry.values?["counter"] {
                values["\(entry.name)_\(dest)"] = counter
                continue
            }

            if entry.parameters?["period"] != nil, let cdataValues = entry.values {
                for (key, value) in cdataValues where key.isUppercased {
                    values["\(entry.name)_\(key)"] = value
                }
            }
        }
        return values
    }

    private static func isDevicesData(_ path: String?) -> Bool {
        guard let path else { return false }
        if path == "/devices/data" { return true }
        return path.contains("/devices/") && path.contains("/data")
    }

    private static func isDevicesCData(_ path: String?) -> Bool {
        guard let path else { return false }
        if path == "/devices/cdata" { return true }
        return path.contains("/cdata")
    }

    private static func decodePayloadArray<T: Decodable>(_ type: T.Type, from data: Data) -> [T]? {
        let decoder = JSONDecoder()
        if let array = try? decoder.decode([T].self, from: data) { return array }
        if let single = try? decoder.decode(T.self, from: data) { return [single] }
        return nil
    }

    private static func decodeConfigsFile(_ data: Data) -> [TydomCacheMutation]? {
        guard let payload = try? JSONDecoder().decode(ConfigsFilePayload.self, from: data) else {
            return nil
        }

        var mutations: [TydomCacheMutation] = []
        for endpoint in payload.endpoints {
            let uniqueId = "\(endpoint.idEndpoint)_\(endpoint.idDevice)"
            let usage = endpoint.lastUsage ?? "unknown"
            let name = usage == "alarm" ? "Tyxal Alarm" : endpoint.name
            let entry = TydomDeviceCacheEntry(uniqueId: uniqueId, name: name, usage: usage, metadata: nil)
            mutations.append(.deviceEntry(entry))
        }

        if let scenarios = payload.scenarios {
            for scenario in scenarios {
                let metadata = TydomScenarioMetadata(
                    id: scenario.id,
                    name: scenario.name ?? "Scenario \(scenario.id)",
                    type: scenario.type ?? "NORMAL",
                    picto: scenario.picto ?? "",
                    ruleId: scenario.ruleId
                )
                mutations.append(.scenarioMetadata(metadata))
            }
        }
        return mutations
    }

    private static func decodeDevicesMeta(_ data: Data) -> [TydomCacheMutation]? {
        guard let payload = try? JSONDecoder().decode([DevicesMetaPayload].self, from: data) else {
            return nil
        }

        var mutations: [TydomCacheMutation] = []
        for device in payload {
            for endpoint in device.endpoints {
                let uniqueId = "\(endpoint.id)_\(device.id)"
                let metadata = (endpoint.metadata ?? []).reduce(into: [String: JSONValue]()) { acc, entry in
                    acc[entry.name] = .object(entry.attributes)
                }
                let entry = TydomDeviceCacheEntry(uniqueId: uniqueId, name: nil, usage: nil, metadata: metadata)
                mutations.append(.deviceEntry(entry))
            }
        }
        return mutations
    }

    private static func decodeDevicesCMeta(_ data: Data) -> (urls: [String], mutations: [TydomCacheMutation])? {
        guard let payload = try? JSONDecoder().decode([DevicesCMetaPayload].self, from: data) else {
            return nil
        }

        var urls: [String] = []
        var mutations: [TydomCacheMutation] = []
        let consoNames = Set(["energyIndex", "energyInstant", "energyDistrib", "energyHisto"])
        for device in payload {
            for endpoint in device.endpoints {
                for entry in endpoint.cmetadata ?? [] {
                    if consoNames.contains(entry.name) {
                        let uniqueId = "\(endpoint.id)_\(device.id)"
                        let entry = TydomDeviceCacheEntry(uniqueId: uniqueId, name: "Tywatt", usage: "conso", metadata: nil)
                        mutations.append(.deviceEntry(entry))
                    }
                    switch entry.name {
                    case "energyIndex":
                        urls.append(contentsOf: urlsForCData(
                            deviceId: device.id,
                            endpointId: endpoint.id,
                            name: entry.name,
                            parameterName: "dest",
                            parameterValueKey: "dest",
                            parameters: entry.parameters ?? [],
                            suffix: "&reset=false"
                        ))
                    case "energyInstant":
                        urls.append(contentsOf: urlsForCData(
                            deviceId: device.id,
                            endpointId: endpoint.id,
                            name: entry.name,
                            parameterName: "unit",
                            parameterValueKey: "unit",
                            parameters: entry.parameters ?? [],
                            suffix: "&reset=false"
                        ))
                    case "energyHisto":
                        urls.append(contentsOf: urlsForCData(
                            deviceId: device.id,
                            endpointId: endpoint.id,
                            name: entry.name,
                            parameterName: "dest",
                            parameterValueKey: "dest",
                            parameters: entry.parameters ?? [],
                            suffix: "&period=YEAR&periodOffset=0"
                        ))
                    case "energyDistrib":
                        urls.append(contentsOf: urlsForCData(
                            deviceId: device.id,
                            endpointId: endpoint.id,
                            name: entry.name,
                            parameterName: "src",
                            parameterValueKey: "src",
                            parameters: entry.parameters ?? [],
                            suffix: "&period=YEAR&periodOffset=0"
                        ))
                    default:
                        continue
                    }
                }
            }
        }
        return (urls, mutations)
    }

    private static func urlsForCData(
        deviceId: Int,
        endpointId: Int,
        name: String,
        parameterName: String,
        parameterValueKey: String,
        parameters: [DevicesCMetaPayload.CMetaParameter],
        suffix: String
    ) -> [String] {
        let values = parameters.first(where: { $0.name == parameterName })?.enumValues ?? []
        return values.map { value in
            "/devices/\(deviceId)/endpoints/\(endpointId)/cdata?name=\(name)&\(parameterValueKey)=\(value)\(suffix)"
        }
    }

    private static func decodeGroupsFile(_ data: Data) -> [TydomGroup]? {
        guard let payload = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { return nil }
        guard let groups = payload["groups"]?.arrayValue else { return [] }
        return groups.compactMap { value in
            value.objectValue.map { TydomGroup(payload: $0) }
        }
    }

    private static func decodeMomentsFile(_ data: Data) -> [TydomMoment]? {
        guard let payload = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { return nil }
        guard let moments = payload["moments"]?.arrayValue else { return [] }
        return moments.compactMap { value in
            value.objectValue.map { TydomMoment(payload: $0) }
        }
    }

    private static func decodeScenariosFile(_ data: Data) -> [TydomScenarioPayload]? {
        guard let payload = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { return nil }
        guard let scenarios = payload["scn"]?.arrayValue else { return [] }
        return scenarios.compactMap { value in
            guard let object = value.objectValue else { return nil }
            guard let id = object["id"]?.numberValue.map(Int.init) else { return nil }
            return TydomScenarioPayload(id: id, payload: object)
        }
    }

    private static func decodeAreasData(_ data: Data) -> [TydomArea]? {
        if let array = try? JSONDecoder().decode([JSONValue].self, from: data) {
            return array.compactMap { value in
                guard let object = value.objectValue else { return nil }
                let id = object["id"]?.numberValue.map(Int.init)
                return TydomArea(id: id, payload: object)
            }
        }

        if let single = try? JSONDecoder().decode(JSONValue.self, from: data),
           let object = single.objectValue {
            let id = object["id"]?.numberValue.map(Int.init)
            return [TydomArea(id: id, payload: object)]
        }

        return nil
    }
}

private struct DevicesDataPayload: Decodable {
    let id: Int
    let endpoints: [Endpoint]

    struct Endpoint: Decodable {
        let id: Int
        let error: Int?
        let data: [Entry]?
    }

    struct Entry: Decodable {
        let name: String
        let value: JSONValue?
        let validity: String?
    }
}

private struct DevicesCDataPayload: Decodable {
    let id: Int
    let endpoints: [Endpoint]

    struct Endpoint: Decodable {
        let id: Int
        let error: Int?
        let cdata: [Entry]?
    }

    struct Entry: Decodable {
        let name: String
        let parameters: [String: JSONValue]?
        let values: [String: JSONValue]?
        let EOR: Bool?
        let payload: [String: JSONValue]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            var payload: [String: JSONValue] = [:]
            for key in container.allKeys {
                payload[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
            }

            guard let nameValue = payload["name"]?.stringValue else {
                let context = DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Missing cdata name"
                )
                throw DecodingError.keyNotFound(DynamicCodingKey(stringValue: "name")!, context)
            }

            self.name = nameValue
            self.parameters = payload["parameters"]?.objectValue
            self.values = payload["values"]?.objectValue
            self.EOR = payload["EOR"]?.boolValue
            self.payload = payload
        }
    }
}

private extension String {
    var isUppercased: Bool {
        guard isEmpty == false else { return false }
        return self == uppercased()
    }
}

private struct ConfigsFilePayload: Decodable {
    let endpoints: [Endpoint]
    let scenarios: [Scenario]?

    struct Endpoint: Decodable {
        let idEndpoint: Int
        let idDevice: Int
        let name: String
        let lastUsage: String?

        private enum CodingKeys: String, CodingKey {
            case idEndpoint = "id_endpoint"
            case idDevice = "id_device"
            case name
            case lastUsage = "last_usage"
        }
    }

    struct Scenario: Decodable {
        let id: Int
        let name: String?
        let type: String?
        let picto: String?
        let ruleId: String?

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case type
            case picto
            case ruleId = "rule_id"
        }
    }
}

private struct DevicesMetaPayload: Decodable {
    let id: Int
    let endpoints: [Endpoint]

    struct Endpoint: Decodable {
        let id: Int
        let metadata: [MetadataEntry]?
    }

    struct MetadataEntry: Decodable {
        let name: String
        let attributes: [String: JSONValue]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            var name: String?
            var attributes: [String: JSONValue] = [:]

            for key in container.allKeys {
                if key.stringValue == "name" {
                    name = try container.decode(String.self, forKey: key)
                } else {
                    attributes[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
                }
            }

            guard let resolvedName = name else {
                let context = DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Missing metadata name"
                )
                throw DecodingError.keyNotFound(DynamicCodingKey(stringValue: "name")!, context)
            }

            self.name = resolvedName
            self.attributes = attributes
        }
    }
}

private struct DevicesCMetaPayload: Decodable {
    let id: Int
    let endpoints: [Endpoint]

    struct Endpoint: Decodable {
        let id: Int
        let cmetadata: [CMetaEntry]?
    }

    struct CMetaEntry: Decodable {
        let name: String
        let parameters: [CMetaParameter]?
    }

    struct CMetaParameter: Decodable {
        let name: String
        let enumValues: [String]

        private enum CodingKeys: String, CodingKey {
            case name
            case enumValues = "enum_values"
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
}
