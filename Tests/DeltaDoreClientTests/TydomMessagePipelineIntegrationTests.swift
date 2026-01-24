import Foundation
import Testing
@testable import DeltaDoreClient

@Test func tydomMessagePipeline_mapsDataToMessages() async {
    // Given
    let (stream, continuation) = AsyncStream<Data>.makeStream()
    let cache = TydomDeviceCacheStore()
    let hydrator = TydomMessageHydrator(dependencies: .live(cache))
    let executor = TydomMessageEffectExecutor(dependencies: .init(
        sendCommand: { _ in },
        pollScheduler: { _, _ in },
        pollOnceScheduled: {},
        onPong: {},
        onCDataReplyChunk: { _ in }
    ))

    await cache.upsert(TydomDeviceCacheEntry(uniqueId: "2_1", name: "Living Room", usage: "shutter"))

    let infoPayload = httpResponse(
        uriOrigin: "/info",
        transactionId: "t1",
        body: "{\"version\":\"1.0\"}"
    )

    let devicesPayload = httpResponse(
        uriOrigin: "/devices/data",
        transactionId: "t2",
        body: """
        [
          {"id": 1, "endpoints": [
            {"id": 2, "error": 0, "data": [
              {"name": "level", "value": 10, "validity": "upToDate"}
            ]}
          ]}
        ]
        """
    )

    Task {
        continuation.yield(infoPayload)
        continuation.yield(devicesPayload)
        continuation.finish()
    }

    // When
    let pipeline = stream
        .map { data in TydomRawMessageParser.parse(data) }
        .map { raw in TydomMessageDecoder.decode(raw) }
        .map { decoded in await hydrator.hydrate(decoded) }
        .map { (hydrated: TydomHydratedEnvelope) in
            Task { await executor.enqueue(hydrated.effects) }
            return hydrated.message
        }

    var messages: [TydomMessage] = []
    for await message in pipeline {
        messages.append(message)
    }

    // Then
    #expect(messages.count == 2)
    if case .gatewayInfo(_, let transactionId) = messages[0] {
        #expect(transactionId == "t1")
    } else {
        #expect(Bool(false), "Expected gateway info")
    }

    if case .devices(let devices, let transactionId) = messages[1] {
        #expect(transactionId == "t2")
        #expect(devices.count == 1)
        #expect(devices[0].name == "Living Room")
        #expect(devices[0].data["level"] == JSONValue.number(10))
    } else {
        #expect(Bool(false), "Expected devices message")
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
