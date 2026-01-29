import Foundation

public struct TydomCommand: Sendable, Equatable {
    public let request: String

    public init(request: String) {
        self.request = request
    }
}

extension TydomCommand {
    enum Method: String, Sendable {
        case get = "GET"
        case put = "PUT"
        case post = "POST"
    }

    public enum PutDataValue: Sendable, Equatable {
        case string(String)
        case bool(Bool)
        case int(Int)
        case null
    }

    public enum DeviceDataValue: Sendable, Equatable {
        case string(String)
        case bool(Bool)
        case int(Int)
        case null
    }

    typealias TransactionIdGenerator = @Sendable () -> String

    static func request(
        method: Method,
        path: String,
        body: String? = nil,
        transactionId: String = defaultTransactionId(),
        additionalHeaders: [String: String] = [:]
    ) -> TydomCommand {
        let contentLength = body?.data(using: .utf8)?.count ?? 0
        var lines = [
            "\(method.rawValue) \(path) HTTP/1.1",
            "Content-Length: \(contentLength)",
            "Content-Type: \(contentType)",
            "Transac-Id: \(transactionId)"
        ]

        let reservedHeaders = Set(["content-length", "content-type", "transac-id"])
        let filteredHeaders = additionalHeaders.filter { key, _ in
            reservedHeaders.contains(key.lowercased()) == false
        }
        for key in filteredHeaders.keys.sorted(by: { $0.lowercased() < $1.lowercased() }) {
            if let value = filteredHeaders[key] {
                lines.append("\(key): \(value)")
            }
        }

        var request = lines.joined(separator: "\r\n")
        if let body {
            request += "\r\n\r\n\(body)\r\n\r\n"
        } else {
            request += "\r\n\r\n"
        }
        return TydomCommand(request: request)
    }

    public static func info(transactionId: String = defaultTransactionId()) -> TydomCommand {
        request(method: .get, path: "/info", transactionId: transactionId)
    }

    public static func localClaim(transactionId: String = defaultTransactionId()) -> TydomCommand {
        request(method: .get, path: "/configs/gateway/local_claim", transactionId: transactionId)
    }

    public static func geoloc(transactionId: String = defaultTransactionId()) -> TydomCommand {
        request(method: .get, path: "/configs/gateway/geoloc", transactionId: transactionId)
    }

    public static func apiMode(transactionId: String = defaultTransactionId()) -> TydomCommand {
        request(method: .put, path: "/configs/gateway/api_mode", transactionId: transactionId)
    }

    public static func refreshAll(transactionId: String = defaultTransactionId()) -> TydomCommand {
        request(method: .post, path: "/refresh/all", transactionId: transactionId)
    }

    public static func ping(transactionId: String = defaultTransactionId()) -> TydomCommand {
        request(method: .get, path: "/ping", transactionId: transactionId)
    }

    public static func devicesMeta(transactionId: String = defaultTransactionId()) -> TydomCommand {
        request(method: .get, path: "/devices/meta", transactionId: transactionId)
    }

    public static func devicesData(transactionId: String = defaultTransactionId()) -> TydomCommand {
        request(method: .get, path: "/devices/data", transactionId: transactionId)
    }

    public static func configsFile(transactionId: String = defaultTransactionId()) -> TydomCommand {
        request(method: .get, path: "/configs/file", transactionId: transactionId)
    }

    public static func devicesCmeta(transactionId: String = defaultTransactionId()) -> TydomCommand {
        request(method: .get, path: "/devices/cmeta", transactionId: transactionId)
    }

    public static func areasMeta(transactionId: String = defaultTransactionId()) -> TydomCommand {
        request(method: .get, path: "/areas/meta", transactionId: transactionId)
    }

    public static func areasCmeta(transactionId: String = defaultTransactionId()) -> TydomCommand {
        request(method: .get, path: "/areas/cmeta", transactionId: transactionId)
    }

    public static func areasData(transactionId: String = defaultTransactionId()) -> TydomCommand {
        request(method: .get, path: "/areas/data", transactionId: transactionId)
    }

    public static func momentsFile(transactionId: String = defaultTransactionId()) -> TydomCommand {
        request(method: .get, path: "/moments/file", transactionId: transactionId)
    }

    public static func scenariosFile(transactionId: String = defaultTransactionId()) -> TydomCommand {
        request(method: .get, path: "/scenarios/file", transactionId: transactionId)
    }

    public static func activateScenario(_ scenarioId: String, transactionId: String = defaultTransactionId()) -> TydomCommand {
        request(method: .put, path: "/scenarios/\(scenarioId)", transactionId: transactionId)
    }

    public static func groupsFile(transactionId: String = defaultTransactionId()) -> TydomCommand {
        request(method: .get, path: "/groups/file", transactionId: transactionId)
    }

    public static func deviceData(deviceId: String, transactionId: String = defaultTransactionId()) -> TydomCommand {
        request(method: .get, path: "/devices/\(deviceId)/endpoints/\(deviceId)/data", transactionId: transactionId)
    }

    public static func pollDeviceData(url: String, transactionId: String = defaultTransactionId()) -> TydomCommand {
        request(method: .get, path: url, transactionId: transactionId)
    }

    public static func updateFirmware(transactionId: String = defaultTransactionId()) -> TydomCommand {
        request(method: .put, path: "/configs/gateway/update", transactionId: transactionId)
    }

    public static func putData(
        path: String,
        name: String,
        value: PutDataValue,
        transactionId: String = "0"
    ) -> TydomCommand {
        let body = putDataBody(name: name, value: value)
        return request(method: .put, path: path, body: body, transactionId: transactionId)
    }

    public static func putDevicesData(
        deviceId: String,
        endpointId: String,
        name: String,
        value: DeviceDataValue,
        transactionId: String = "0"
    ) -> TydomCommand {
        let body = deviceDataBody(name: name, value: value)
        return request(
            method: .put,
            path: "/devices/\(deviceId)/endpoints/\(endpointId)/data",
            body: body,
            transactionId: transactionId
        )
    }

    public static func alarmCData(
        deviceId: String,
        endpointId: String,
        alarmPin: String?,
        value: String,
        zoneId: String? = nil,
        legacyZones: Bool = false,
        transactionId: String = "0"
    ) -> [TydomCommand] {
        let pin = alarmPin ?? ""
        if legacyZones {
            guard let zoneId, zoneId.isEmpty == false else { return [] }
            let zones = zoneId.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.isEmpty == false }
            return zones.map { zone in
                alarmCDataSingle(
                    deviceId: deviceId,
                    endpointId: endpointId,
                    alarmPin: pin,
                    value: value,
                    zoneId: Substring(zone),
                    legacyZones: true,
                    transactionId: transactionId
                )
            }
        }

        return [
            alarmCDataSingle(
                deviceId: deviceId,
                endpointId: endpointId,
                alarmPin: pin,
                value: value,
                zoneId: zoneId.map { Substring($0) },
                legacyZones: false,
                transactionId: transactionId
            )
        ]
    }

    public static func ackEventsCData(
        deviceId: String,
        endpointId: String,
        alarmPin: String?,
        transactionId: String = "0"
    ) -> TydomCommand {
        let pin = alarmPin ?? ""
        return putData(
            path: "/devices/\(deviceId)/endpoints/\(endpointId)/cdata?name=ackEventCmd",
            name: "pwd",
            value: .string(pin),
            transactionId: transactionId
        )
    }

    public static func historicCData(
        deviceId: String,
        endpointId: String,
        eventType: String? = nil,
        indexStart: Int = 0,
        nbElement: Int = 10,
        transactionId: String = defaultTransactionId()
    ) -> TydomCommand {
        let type = eventType ?? "ALL"
        let path = "/devices/\(deviceId)/endpoints/\(endpointId)/cdata?name=histo&type=\(type)&indexStart=\(indexStart)&nbElem=\(nbElement)"
        return request(method: .get, path: path, transactionId: transactionId)
    }

    public static func defaultTransactionId(now: @Sendable () -> Date = Date.init) -> String {
        let milliseconds = Int(now().timeIntervalSince1970 * 1000)
        return String(milliseconds)
    }
}

private let contentType = "application/json; charset=UTF-8"

private extension TydomCommand {
    static func putDataBody(name: String, value: PutDataValue) -> String {
        let valueString: String
        switch value {
        case .null:
            valueString = "null"
        case .bool(let flag):
            valueString = String(flag).lowercased()
        case .int(let number):
            valueString = String(number)
        case .string(let string):
            valueString = string
        }
        return "{\"\(name)\":\"\(valueString)\"}"
    }

    static func deviceDataBody(name: String, value: DeviceDataValue) -> String {
        switch value {
        case .null:
            return "[{\"name\":\"\(name)\",\"value\":null}]"
        case .bool(let flag):
            return "[{\"name\":\"\(name)\",\"value\":\(String(flag).lowercased())}]"
        case .int(let number):
            return "[{\"name\":\"\(name)\",\"value\":\"\(number)\"}]"
        case .string(let string):
            return "[{\"name\":\"\(name)\",\"value\":\"\(string)\"}]"
        }
    }

    static func alarmCDataSingle(
        deviceId: String,
        endpointId: String,
        alarmPin: String,
        value: String,
        zoneId: Substring?,
        legacyZones: Bool,
        transactionId: String
    ) -> TydomCommand {
        let cmd: String
        let body: String

        if let zoneId, zoneId.isEmpty == false {
            if legacyZones {
                cmd = "partCmd"
                body = "{\"value\":\"\(value)\",\"part\":\"\(zoneId)\"}"
            } else {
                cmd = "zoneCmd"
                body = "{\"value\":\"\(value)\",\"pwd\":\"\(alarmPin)\",\"zones\":\"[\(zoneId)]\"}"
            }
        } else {
            cmd = "alarmCmd"
            body = "{\"value\":\"\(value)\",\"pwd\":\"\(alarmPin)\"}"
        }

        return request(
            method: .put,
            path: "/devices/\(deviceId)/endpoints/\(endpointId)/cdata?name=\(cmd)",
            body: body,
            transactionId: transactionId
        )
    }
}
