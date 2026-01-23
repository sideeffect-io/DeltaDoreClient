import Foundation

public struct TydomMessageDecoderDependencies: Sendable {
    public let deviceInfo: @Sendable (String) async -> TydomDeviceInfo?
    public let upsertDeviceCacheEntry: @Sendable (TydomDeviceCacheEntry) async -> Void

    public init(
        deviceInfo: @escaping @Sendable (String) async -> TydomDeviceInfo?,
        upsertDeviceCacheEntry: @escaping @Sendable (TydomDeviceCacheEntry) async -> Void
    ) {
        self.deviceInfo = deviceInfo
        self.upsertDeviceCacheEntry = upsertDeviceCacheEntry
    }
}

public struct TydomDeviceCacheEntry: Sendable, Equatable {
    public let uniqueId: String
    public var name: String?
    public var usage: String?
    public var metadata: [String: JSONValue]?

    public init(
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

public struct TydomMessageDecoder: Sendable {
    private let dependencies: TydomMessageDecoderDependencies
    private let httpParser: TydomHTTPParser

    public init(dependencies: TydomMessageDecoderDependencies, httpParser: TydomHTTPParser = TydomHTTPParser()) {
        self.dependencies = dependencies
        self.httpParser = httpParser
    }

    public func decode(_ data: Data) async -> TydomMessage {
        switch httpParser.parse(data) {
        case .failure(let error):
            return .raw(TydomRawMessage(
                payload: data,
                frame: nil,
                uriOrigin: nil,
                transactionId: nil,
                parseError: String(describing: error)
            ))
        case .success(let frame):
            return await decodeFrame(frame, payload: data)
        }
    }

    private func decodeFrame(_ frame: TydomHTTPFrame, payload: Data) async -> TydomMessage {
        let uriOrigin = frame.uriOrigin
        let transactionId = frame.transactionId
        guard let body = frame.body, body.isEmpty == false else {
            return .raw(TydomRawMessage(
                payload: payload,
                frame: frame,
                uriOrigin: uriOrigin,
                transactionId: transactionId,
                parseError: nil
            ))
        }

        if uriOrigin == "/info" {
            if let info = decodeGatewayInfo(body) {
                return .gatewayInfo(info, transactionId: transactionId)
            }
            return .raw(TydomRawMessage(
                payload: payload,
                frame: frame,
                uriOrigin: uriOrigin,
                transactionId: transactionId,
                parseError: nil
            ))
        }

        if uriOrigin == "/configs/file" {
            let updated = await decodeConfigsFile(body)
            if updated {
                return .raw(TydomRawMessage(
                    payload: payload,
                    frame: frame,
                    uriOrigin: uriOrigin,
                    transactionId: transactionId,
                    parseError: nil
                ))
            }
        }

        if uriOrigin == "/devices/meta" {
            let updated = await decodeDevicesMeta(body)
            if updated {
                return .raw(TydomRawMessage(
                    payload: payload,
                    frame: frame,
                    uriOrigin: uriOrigin,
                    transactionId: transactionId,
                    parseError: nil
                ))
            }
        }

        if isDevicesData(uriOrigin) {
            if let devices = await decodeDevicesData(body), devices.isEmpty == false {
                return .devices(devices, transactionId: transactionId)
            }
            return .raw(TydomRawMessage(
                payload: payload,
                frame: frame,
                uriOrigin: uriOrigin,
                transactionId: transactionId,
                parseError: nil
            ))
        }

        if isDevicesCData(uriOrigin) {
            if let devices = await decodeDevicesCData(body), devices.isEmpty == false {
                return .devices(devices, transactionId: transactionId)
            }
            return .raw(TydomRawMessage(
                payload: payload,
                frame: frame,
                uriOrigin: uriOrigin,
                transactionId: transactionId,
                parseError: nil
            ))
        }

        return .raw(TydomRawMessage(
            payload: payload,
            frame: frame,
            uriOrigin: uriOrigin,
            transactionId: transactionId,
            parseError: nil
        ))
    }

    private func decodeGatewayInfo(_ data: Data) -> TydomGatewayInfo? {
        guard let payload = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
            return nil
        }
        return TydomGatewayInfo(payload: payload)
    }

    private func decodeDevicesData(_ data: Data) async -> [TydomDevice]? {
        guard let payload = decodePayloadArray(DevicesDataPayload.self, from: data) else { return nil }

        var devices: [TydomDevice] = []
        for device in payload {
            for endpoint in device.endpoints {
                let uniqueId = "\(endpoint.id)_\(device.id)"
                guard let info = await dependencies.deviceInfo(uniqueId) else { continue }
                let values = extractDataValues(from: endpoint)
                let device = TydomDevice(
                    id: device.id,
                    endpointId: endpoint.id,
                    uniqueId: uniqueId,
                    name: info.name,
                    usage: info.usage,
                    kind: TydomDeviceKind.fromUsage(info.usage),
                    data: values,
                    metadata: info.metadata
                )
                devices.append(device)
            }
        }
        return devices
    }

    private func extractDataValues(from endpoint: DevicesDataPayload.Endpoint) -> [String: JSONValue] {
        guard endpoint.error == nil || endpoint.error == 0 else { return [:] }
        guard let entries = endpoint.data else { return [:] }
        var values: [String: JSONValue] = [:]
        for entry in entries {
            guard entry.validity == "upToDate", let value = entry.value else { continue }
            values[entry.name] = value
        }
        return values
    }

    private func decodeDevicesCData(_ data: Data) async -> [TydomDevice]? {
        guard let payload = decodePayloadArray(DevicesCDataPayload.self, from: data) else { return nil }

        var devices: [TydomDevice] = []
        for device in payload {
            for endpoint in device.endpoints {
                guard endpoint.error == nil || endpoint.error == 0 else { continue }
                let uniqueId = "\(endpoint.id)_\(device.id)"
                guard let info = await dependencies.deviceInfo(uniqueId) else { continue }
                guard info.usage == "conso" else { continue }

                let values = extractCDataValues(from: endpoint)
                guard values.isEmpty == false else { continue }

                let device = TydomDevice(
                    id: device.id,
                    endpointId: endpoint.id,
                    uniqueId: uniqueId,
                    name: info.name,
                    usage: info.usage,
                    kind: TydomDeviceKind.fromUsage(info.usage),
                    data: values,
                    metadata: info.metadata
                )
                devices.append(device)
            }
        }
        return devices
    }

    private func extractCDataValues(from endpoint: DevicesCDataPayload.Endpoint) -> [String: JSONValue] {
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

    private func isDevicesData(_ path: String?) -> Bool {
        guard let path else { return false }
        if path == "/devices/data" { return true }
        return path.contains("/devices/") && path.contains("/data")
    }

    private func isDevicesCData(_ path: String?) -> Bool {
        guard let path else { return false }
        if path == "/devices/cdata" { return true }
        return path.contains("/cdata")
    }

    private func decodePayloadArray<T: Decodable>(_ type: T.Type, from data: Data) -> [T]? {
        let decoder = JSONDecoder()
        if let array = try? decoder.decode([T].self, from: data) { return array }
        if let single = try? decoder.decode(T.self, from: data) { return [single] }
        return nil
    }

    private func decodeConfigsFile(_ data: Data) async -> Bool {
        guard let payload = try? JSONDecoder().decode(ConfigsFilePayload.self, from: data) else {
            return false
        }

        for endpoint in payload.endpoints {
            let uniqueId = "\(endpoint.idEndpoint)_\(endpoint.idDevice)"
            let usage = endpoint.lastUsage ?? "unknown"
            let name = usage == "alarm" ? "Tyxal Alarm" : endpoint.name
            let entry = TydomDeviceCacheEntry(uniqueId: uniqueId, name: name, usage: usage, metadata: nil)
            await dependencies.upsertDeviceCacheEntry(entry)
        }
        return true
    }

    private func decodeDevicesMeta(_ data: Data) async -> Bool {
        guard let payload = try? JSONDecoder().decode([DevicesMetaPayload].self, from: data) else {
            return false
        }

        for device in payload {
            for endpoint in device.endpoints {
                let uniqueId = "\(endpoint.id)_\(device.id)"
                let metadata = (endpoint.metadata ?? []).reduce(into: [String: JSONValue]()) { acc, entry in
                    acc[entry.name] = .object(entry.attributes)
                }
                let entry = TydomDeviceCacheEntry(uniqueId: uniqueId, name: nil, usage: nil, metadata: metadata)
                await dependencies.upsertDeviceCacheEntry(entry)
            }
        }
        return true
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
