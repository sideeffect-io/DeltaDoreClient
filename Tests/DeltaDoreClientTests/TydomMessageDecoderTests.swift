import Foundation
import Testing
@testable import DeltaDoreClient

@Test func tydomMessageDecoder_decodesGatewayInfo() async {
    // Given
    let dependencies = TydomMessageDecoderDependencies(
        deviceInfo: { _ in nil },
        upsertDeviceCacheEntry: { _ in }
    )
    let decoder = TydomMessageDecoder(dependencies: dependencies)

    let json = "{\"version\":\"1.0\",\"mac\":\"AA:BB\"}"
    let payload = httpResponse(
        uriOrigin: "/info",
        transactionId: "123",
        body: json
    )

    // When
    let message = await decoder.decode(payload)

    // Then
    if case .gatewayInfo(let info, let transactionId) = message {
        #expect(transactionId == "123")
        #expect(info.payload["version"] == JSONValue.string("1.0"))
        #expect(info.payload["mac"] == JSONValue.string("AA:BB"))
        } else {
            #expect(Bool(false), "Expected gateway info")
        }
}

@Test func tydomMessageDecoder_decodesDevicesDataUsingCache() async {
    // Given
    let dependencies = TydomMessageDecoderDependencies(
        deviceInfo: { uniqueId in
            if uniqueId == "2_1" {
                return TydomDeviceInfo(name: "Living Room", usage: "shutter", metadata: nil)
            }
                return nil
            },
            upsertDeviceCacheEntry: { _ in }
        )
        let decoder = TydomMessageDecoder(dependencies: dependencies)

        let json = """
        [
          {"id": 1, "endpoints": [
            {"id": 2, "error": 0, "data": [
              {"name": "level", "value": 50, "validity": "upToDate"}
            ]}
          ]}
        ]
        """
        let payload = httpResponse(
            uriOrigin: "/devices/data",
        transactionId: "456",
        body: json
    )

    // When
    let message = await decoder.decode(payload)

    // Then
    if case .devices(let devices, let transactionId) = message {
        #expect(transactionId == "456")
        #expect(devices.count == 1)
        let device = devices[0]
            #expect(device.id == 1)
            #expect(device.endpointId == 2)
            #expect(device.uniqueId == "2_1")
            #expect(device.name == "Living Room")
            #expect(device.usage == "shutter")
            #expect(device.kind == TydomDeviceKind.shutter)
            #expect(device.data["level"] == JSONValue.number(50))
        } else {
            #expect(Bool(false), "Expected devices message")
        }
}

@Test func tydomMessageDecoder_decodesDevicesCDataForConsumption() async {
    // Given
    let dependencies = TydomMessageDecoderDependencies(
        deviceInfo: { uniqueId in
            if uniqueId == "1_10" {
                return TydomDeviceInfo(name: "Energy", usage: "conso", metadata: nil)
            }
                return nil
            },
            upsertDeviceCacheEntry: { _ in }
        )
        let decoder = TydomMessageDecoder(dependencies: dependencies)

        let json = """
        [
          {"id": 10, "endpoints": [
            {"id": 1, "error": 0, "cdata": [
              {"name": "energyIndex", "parameters": {"dest": "ELEC"}, "values": {"counter": 123}}
            ]}
          ]}
        ]
        """
        let payload = httpResponse(
            uriOrigin: "/devices/10/endpoints/1/cdata?name=energyIndex",
        transactionId: "789",
        body: json
    )

    // When
    let message = await decoder.decode(payload)

    // Then
    if case .devices(let devices, let transactionId) = message {
        #expect(transactionId == "789")
        #expect(devices.count == 1)
        let device = devices[0]
            #expect(device.name == "Energy")
            #expect(device.usage == "conso")
            #expect(device.kind == TydomDeviceKind.energy)
            #expect(device.data["energyIndex_ELEC"] == JSONValue.number(123))
        } else {
            #expect(Bool(false), "Expected devices message")
        }
}

@Test func tydomMessageDecoder_unsupportedMessageIsRaw() async {
    // Given
    let dependencies = TydomMessageDecoderDependencies(
        deviceInfo: { _ in nil },
        upsertDeviceCacheEntry: { _ in }
    )
        let decoder = TydomMessageDecoder(dependencies: dependencies)

        let payload = httpResponse(
            uriOrigin: "/unknown",
        transactionId: "000",
        body: "{\"foo\":\"bar\"}"
    )

    // When
    let message = await decoder.decode(payload)

    // Then
    if case .raw(let raw) = message {
        #expect(raw.uriOrigin == "/unknown")
        #expect(raw.transactionId == "000")
        } else {
            #expect(Bool(false), "Expected raw message")
        }
}

@Test func tydomMessageDecoder_configsFileUpdatesCache() async {
    // Given
    let cache = TydomDeviceCacheStore()
    let dependencies = TydomMessageDecoderDependencies.fromDeviceCacheStore(cache)
    let decoder = TydomMessageDecoder(dependencies: dependencies)

        let body = """
        {"endpoints":[
          {"id_endpoint":2,"id_device":1,"name":"Living Room","last_usage":"shutter"},
          {"id_endpoint":3,"id_device":1,"name":"Alarm","last_usage":"alarm"}
        ]}
        """
    let payload = httpResponse(uriOrigin: "/configs/file", transactionId: "111", body: body)

    // When
    _ = await decoder.decode(payload)

    // Then
    let shutter = await cache.deviceInfo(for: "2_1")
    #expect(shutter?.name == "Living Room")
    #expect(shutter?.usage == "shutter")

        let alarm = await cache.deviceInfo(for: "3_1")
        #expect(alarm?.name == "Tyxal Alarm")
        #expect(alarm?.usage == "alarm")
}

@Test func tydomMessageDecoder_devicesMetaUpdatesCache() async {
    // Given
    let cache = TydomDeviceCacheStore()
    let dependencies = TydomMessageDecoderDependencies.fromDeviceCacheStore(cache)
    let decoder = TydomMessageDecoder(dependencies: dependencies)

        let body = """
        [
          {"id":1,"endpoints":[
            {"id":2,"metadata":[{"name":"position","min":0,"max":100}]}
          ]}
        ]
        """
    let payload = httpResponse(uriOrigin: "/devices/meta", transactionId: "222", body: body)

    // When
    _ = await decoder.decode(payload)

    await cache.upsert(TydomDeviceCacheEntry(uniqueId: "2_1", name: "Living Room", usage: "shutter"))
    let device = await cache.deviceInfo(for: "2_1")

    // Then
    #expect(device?.metadata?["position"] == JSONValue.object(["min": .number(0), "max": .number(100)]))
}

private func httpResponse(uriOrigin: String, transactionId: String, body: String) -> Data {
    let bodyData = Data(body.utf8)
    let response = "HTTP/1.1 200 OK\r\n" +
        "Content-Length: \(bodyData.count)\r\n" +
        "Uri-Origin: \(uriOrigin)\r\n" +
        "Transac-Id: \(transactionId)\r\n" +
        "\r\n" +
        body
    return Data(response.utf8)
}
