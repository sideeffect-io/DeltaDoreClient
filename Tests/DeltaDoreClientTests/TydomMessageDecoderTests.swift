import Foundation
import Testing
@testable import DeltaDoreClient

@Test func tydomMessageDecoder_decodesGatewayInfo() async {
    // Given
    let pipeline = MessagePipelineHarness(
        deviceInfo: { _ in nil },
        applyCacheMutation: { _ in }
    )

    let json = "{\"version\":\"1.0\",\"mac\":\"AA:BB\"}"
    let payload = httpResponse(
        uriOrigin: "/info",
        transactionId: "123",
        body: json
    )

    // When
    let message = await pipeline.decodeAndHydrate(payload)

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
    let pipeline = MessagePipelineHarness(
        deviceInfo: { uniqueId in
            if uniqueId == "2_1" {
                return TydomDeviceInfo(name: "Living Room", usage: "shutter", metadata: nil)
            }
            return nil
        },
        applyCacheMutation: { _ in }
    )

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
    let message = await pipeline.decodeAndHydrate(payload)

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
    let pipeline = MessagePipelineHarness(
        deviceInfo: { uniqueId in
            if uniqueId == "1_10" {
                return TydomDeviceInfo(name: "Energy", usage: "conso", metadata: nil)
            }
            return nil
        },
        applyCacheMutation: { _ in }
    )

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
    let message = await pipeline.decodeAndHydrate(payload)

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
    let pipeline = MessagePipelineHarness(
        deviceInfo: { _ in nil },
        applyCacheMutation: { _ in }
    )

    let payload = httpResponse(
        uriOrigin: "/unknown",
        transactionId: "000",
        body: "{\"foo\":\"bar\"}"
    )

    // When
    let message = await pipeline.decodeAndHydrate(payload)

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
    let pipeline = MessagePipelineHarness(
        deviceInfo: { uniqueId in
            await cache.deviceInfo(for: uniqueId)
        },
        applyCacheMutation: { mutation in
            switch mutation {
            case .deviceEntry(let entry):
                await cache.upsert(entry)
            case .scenarioMetadata:
                break
            }
        }
    )

    let body = """
    {"endpoints":[
      {"id_endpoint":2,"id_device":1,"name":"Living Room","last_usage":"shutter"},
      {"id_endpoint":3,"id_device":1,"name":"Alarm","last_usage":"alarm"}
    ]}
    """
    let payload = httpResponse(uriOrigin: "/configs/file", transactionId: "111", body: body)

    // When
    _ = await pipeline.decodeAndHydrate(payload)

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
    let pipeline = MessagePipelineHarness(
        deviceInfo: { uniqueId in
            await cache.deviceInfo(for: uniqueId)
        },
        applyCacheMutation: { mutation in
            switch mutation {
            case .deviceEntry(let entry):
                await cache.upsert(entry)
            case .scenarioMetadata:
                break
            }
        }
    )

    let body = """
    [
      {"id":1,"endpoints":[
        {"id":2,"metadata":[{"name":"position","min":0,"max":100}]}
      ]}
    ]
    """
    let payload = httpResponse(uriOrigin: "/devices/meta", transactionId: "222", body: body)

    // When
    _ = await pipeline.decodeAndHydrate(payload)

    await cache.upsert(TydomDeviceCacheEntry(uniqueId: "2_1", name: "Living Room", usage: "shutter"))
    let device = await cache.deviceInfo(for: "2_1")

    // Then
    #expect(device?.metadata?["position"] == JSONValue.object(["min": .number(0), "max": .number(100)]))
}

@Test func tydomMessageDecoder_devicesCmetaSchedulesPolling() async {
    // Given
    let body = """
    [
      {"id":1,"endpoints":[
        {"id":2,"cmetadata":[
          {"name":"energyIndex","parameters":[{"name":"dest","enum_values":["ELEC","GAS"]}]},
          {"name":"energyInstant","parameters":[{"name":"unit","enum_values":["ELEC_A"]}]}
        ]}
      ]}
    ]
    """
    let payload = httpResponse(uriOrigin: "/devices/cmeta", transactionId: "333", body: body)
    let raw = TydomRawMessageParser.parse(payload)

    // When
    let envelope = TydomMessageDecoder.decode(raw)

    // Then
    #expect(envelope.effects.count == 1)
    if case .schedulePoll(let urls, let intervalSeconds) = envelope.effects[0] {
        #expect(intervalSeconds == 60)
        #expect(urls.contains("/devices/1/endpoints/2/cdata?name=energyIndex&dest=ELEC&reset=false"))
        #expect(urls.contains("/devices/1/endpoints/2/cdata?name=energyIndex&dest=GAS&reset=false"))
        #expect(urls.contains("/devices/1/endpoints/2/cdata?name=energyInstant&unit=ELEC_A&reset=false"))
    } else {
        #expect(Bool(false), "Expected schedulePoll effect")
    }
}

@Test func tydomMessageDecoder_eventsTriggerRefreshAll() async {
    // Given
    let payload = httpResponse(uriOrigin: "/events", transactionId: "444", body: "{}")
    let raw = TydomRawMessageParser.parse(payload)

    // When
    let envelope = TydomMessageDecoder.decode(raw)

    // Then
    #expect(envelope.effects == [.refreshAll])
}

@Test func tydomMessageDecoder_areasDataProducesAreasMessage() async {
    // Given
    let pipeline = MessagePipelineHarness(
        deviceInfo: { _ in nil },
        applyCacheMutation: { _ in }
    )

    let body = """
    [
      {"id": 101, "data": [{"name": "level", "value": 20, "validity": "upToDate"}]},
      {"id": 102, "data": []}
    ]
    """
    let payload = httpResponse(uriOrigin: "/areas/data", transactionId: "445", body: body)

    // When
    let message = await pipeline.decodeAndHydrate(payload)

    // Then
    if case .areas(let areas, let transactionId) = message {
        #expect(transactionId == "445")
        #expect(areas.count == 2)
        #expect(areas[0].id == 101)
    } else {
        #expect(Bool(false), "Expected areas message")
    }
}

@Test func tydomMessageDecoder_scenariosMergeMetadata() async {
    // Given
    let scenarioStore = TydomScenarioMetadataStore()
    let pipeline = MessagePipelineHarness(
        deviceInfo: { _ in nil },
        scenarioMetadata: { id in
            await scenarioStore.metadata(for: id)
        },
        applyCacheMutation: { mutation in
            switch mutation {
            case .deviceEntry:
                break
            case .scenarioMetadata(let metadata):
                await scenarioStore.upsert(metadata)
            }
        }
    )

    let configsBody = """
    {"endpoints":[],
     "scenarios":[{"id":1,"name":"Wake","type":"NORMAL","picto":"SUN","rule_id":"r1"}]}
    """
    let configsPayload = httpResponse(uriOrigin: "/configs/file", transactionId: "555", body: configsBody)

    let scenariosBody = """
    {"scn":[{"id":1,"grpAct":[1]}]}
    """
    let scenariosPayload = httpResponse(uriOrigin: "/scenarios/file", transactionId: "556", body: scenariosBody)

    // When
    _ = await pipeline.decodeAndHydrate(configsPayload)
    let message = await pipeline.decodeAndHydrate(scenariosPayload)

    // Then
    if case .scenarios(let scenarios, let transactionId) = message {
        #expect(transactionId == "556")
        #expect(scenarios.count == 1)
        #expect(scenarios[0].name == "Wake")
        #expect(scenarios[0].type == "NORMAL")
        #expect(scenarios[0].picto == "SUN")
        #expect(scenarios[0].ruleId == "r1")
    } else {
        #expect(Bool(false), "Expected scenarios message")
    }
}

@Test func tydomMessageDecoder_alarmCdataCreatesReplyChunkEffect() async {
    // Given
    let pipeline = MessagePipelineHarness(
        deviceInfo: { uniqueId in
            if uniqueId == "1_10" {
                return TydomDeviceInfo(name: "Alarm", usage: "alarm", metadata: nil)
            }
            return nil
        },
        applyCacheMutation: { _ in }
    )

    let body = """
    [
      {"id": 10, "endpoints": [
        {"id": 1, "error": 0, "cdata": [
          {"name": "alarm", "EOR": true, "value": "ON"}
        ]}
      ]}
    ]
    """
    let payload = httpResponse(
        uriOrigin: "/devices/10/endpoints/1/cdata?name=alarmCmd",
        transactionId: "999",
        body: body
    )

    // When
    let envelope = await pipeline.decodeAndHydrateEnvelope(payload)

    // Then
    #expect(envelope.effects.count == 1)
    if case .cdataReplyChunk(let chunk) = envelope.effects[0] {
        #expect(chunk.transactionId == "999")
        #expect(chunk.done == true)
        #expect(chunk.events.count == 1)
    } else {
        #expect(Bool(false), "Expected cdataReplyChunk effect")
    }
}

private struct MessagePipelineHarness: Sendable {
    let hydrator: TydomMessageHydrator

    init(
        deviceInfo: @escaping @Sendable (String) async -> TydomDeviceInfo?,
        scenarioMetadata: @escaping @Sendable (Int) async -> TydomScenarioMetadata? = { _ in nil },
        applyCacheMutation: @escaping @Sendable (TydomCacheMutation) async -> Void
    ) {
        self.hydrator = TydomMessageHydrator(
            dependencies: TydomMessageHydratorDependencies(
                deviceInfo: deviceInfo,
                scenarioMetadata: scenarioMetadata,
                applyCacheMutation: applyCacheMutation
            )
        )
    }

    func decodeAndHydrate(_ data: Data) async -> TydomMessage {
        let raw = TydomRawMessageParser.parse(data)
        let decoded = TydomMessageDecoder.decode(raw)
        let hydrated = await hydrator.hydrate(decoded)
        return hydrated.message
    }

    func decodeAndHydrateEnvelope(_ data: Data) async -> TydomHydratedEnvelope {
        let raw = TydomRawMessageParser.parse(data)
        let decoded = TydomMessageDecoder.decode(raw)
        return await hydrator.hydrate(decoded)
    }
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
