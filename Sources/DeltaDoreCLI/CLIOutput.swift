import Foundation
import DeltaDoreClient

func render(message: TydomMessage) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let json = messageToJSONValue(message)
    guard let data = try? encoder.encode(json) else {
        return "{\"error\":\"Failed to encode message\"}"
    }
    return String(data: data, encoding: .utf8) ?? "{\"error\":\"Failed to encode message\"}"
}

private func messageToJSONValue(_ message: TydomMessage) -> JSONValue {
    switch message {
    case .gatewayInfo(let info, let transactionId):
        return .object([
            "type": .string("gatewayInfo"),
            "transactionId": jsonOptionalString(transactionId),
            "payload": .object(info.payload)
        ])
    case .devices(let devices, let transactionId):
        return .object([
            "type": .string("devices"),
            "transactionId": jsonOptionalString(transactionId),
            "payload": .array(devices.map(deviceToJSONValue))
        ])
    case .scenarios(let scenarios, let transactionId):
        return .object([
            "type": .string("scenarios"),
            "transactionId": jsonOptionalString(transactionId),
            "payload": .array(scenarios.map(scenarioToJSONValue))
        ])
    case .groups(let groups, let transactionId):
        return .object([
            "type": .string("groups"),
            "transactionId": jsonOptionalString(transactionId),
            "payload": .array(groups.map(groupToJSONValue))
        ])
    case .moments(let moments, let transactionId):
        return .object([
            "type": .string("moments"),
            "transactionId": jsonOptionalString(transactionId),
            "payload": .array(moments.map(momentToJSONValue))
        ])
    case .areas(let areas, let transactionId):
        return .object([
            "type": .string("areas"),
            "transactionId": jsonOptionalString(transactionId),
            "payload": .array(areas.map(areaToJSONValue))
        ])
    case .raw(let raw):
        return rawMessageToJSONValue(raw)
    }
}

private func deviceToJSONValue(_ device: TydomDevice) -> JSONValue {
    var object: [String: JSONValue] = [
        "id": .number(Double(device.id)),
        "endpointId": .number(Double(device.endpointId)),
        "uniqueId": .string(device.uniqueId),
        "name": .string(device.name),
        "usage": .string(device.usage),
        "kind": .string(deviceKindString(device.kind)),
        "data": .object(device.data)
    ]
    if let metadata = device.metadata {
        object["metadata"] = .object(metadata)
    } else {
        object["metadata"] = .null
    }
    return .object(object)
}

private func scenarioToJSONValue(_ scenario: TydomScenario) -> JSONValue {
    return .object([
        "id": .number(Double(scenario.id)),
        "name": .string(scenario.name),
        "type": .string(scenario.type),
        "picto": .string(scenario.picto),
        "ruleId": jsonOptionalString(scenario.ruleId),
        "payload": .object(scenario.payload)
    ])
}

private func groupToJSONValue(_ group: TydomGroup) -> JSONValue {
    return .object([
        "payload": .object(group.payload)
    ])
}

private func momentToJSONValue(_ moment: TydomMoment) -> JSONValue {
    return .object([
        "payload": .object(moment.payload)
    ])
}

private func areaToJSONValue(_ area: TydomArea) -> JSONValue {
    return .object([
        "id": area.id.map { .number(Double($0)) } ?? .null,
        "payload": .object(area.payload)
    ])
}

private func rawMessageToJSONValue(_ raw: TydomRawMessage) -> JSONValue {
    var object: [String: JSONValue] = [
        "type": .string("raw"),
        "uriOrigin": jsonOptionalString(raw.uriOrigin),
        "transactionId": jsonOptionalString(raw.transactionId),
        "parseError": jsonOptionalString(raw.parseError)
    ]

    let payload = stringForData(raw.payload)
    object["payload"] = .string(payload.value)
    object["payloadEncoding"] = .string(payload.encoding)

    if let frame = raw.frame {
        object["frame"] = httpFrameToJSONValue(frame)
    } else {
        object["frame"] = .null
    }
    return .object(object)
}

private func httpFrameToJSONValue(_ frame: TydomHTTPFrame) -> JSONValue {
    switch frame {
    case .request(let request):
        var object: [String: JSONValue] = [
            "type": .string("request"),
            "method": .string(request.method),
            "path": .string(request.path),
            "headers": jsonObject(from: request.headers)
        ]
        if let body = request.body {
            let payload = stringForData(body)
            object["body"] = .string(payload.value)
            object["bodyEncoding"] = .string(payload.encoding)
        } else {
            object["body"] = .null
        }
        return .object(object)
    case .response(let response):
        var object: [String: JSONValue] = [
            "type": .string("response"),
            "status": .number(Double(response.status)),
            "reason": jsonOptionalString(response.reason),
            "headers": jsonObject(from: response.headers)
        ]
        if let body = response.body {
            let payload = stringForData(body)
            object["body"] = .string(payload.value)
            object["bodyEncoding"] = .string(payload.encoding)
        } else {
            object["body"] = .null
        }
        return .object(object)
    }
}

private func jsonObject(from headers: [String: String]) -> JSONValue {
    let mapped = headers.mapValues { JSONValue.string($0) }
    return .object(mapped)
}

private func jsonOptionalString(_ value: String?) -> JSONValue {
    guard let value else { return .null }
    return .string(value)
}

private func deviceKindString(_ kind: TydomDeviceKind) -> String {
    switch kind {
    case .shutter:
        return "shutter"
    case .window:
        return "window"
    case .door:
        return "door"
    case .garage:
        return "garage"
    case .gate:
        return "gate"
    case .light:
        return "light"
    case .energy:
        return "energy"
    case .smoke:
        return "smoke"
    case .boiler:
        return "boiler"
    case .alarm:
        return "alarm"
    case .weather:
        return "weather"
    case .water:
        return "water"
    case .thermo:
        return "thermo"
    case .other(let raw):
        return raw
    }
}

private func stringForData(_ data: Data) -> (value: String, encoding: String) {
    if let string = String(data: data, encoding: .utf8) {
        return (string, "utf8")
    }
    return (data.base64EncodedString(), "base64")
}
