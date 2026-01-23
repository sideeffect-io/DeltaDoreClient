import Foundation
import Testing

@testable import DeltaDoreClient

@Test func pingCommandMatchesLegacyFormat() {
    // Given
    let command = TydomCommand.ping(transactionId: "1234567890123")
    let expected = "GET /ping HTTP/1.1\r\nContent-Length: 0\r\nContent-Type: application/json; charset=UTF-8\r\nTransac-Id: 1234567890123\r\n\r\n"

    // When
    let request = command.request

    // Then
    #expect(request == expected)
}

@Test func commandWithBodyIncludesLengthAndBody() {
    // Given
    let body = "{\"value\":true}"
    let expected = "PUT /devices/1 HTTP/1.1\r\nContent-Length: 14\r\nContent-Type: application/json; charset=UTF-8\r\nTransac-Id: 1\r\n\r\n{\"value\":true}\r\n\r\n"

    // When
    let command = TydomCommand.request(method: .put, path: "/devices/1", body: body, transactionId: "1")

    // Then
    #expect(command.request == expected)
}

@Test func putDataFormatsLegacyBody() {
    // Given
    let command = TydomCommand.putData(path: "/devices/1", name: "enabled", value: .bool(true), transactionId: "0")
    let body = "{\"enabled\":\"true\"}"
    let expected = expectedRequest(method: "PUT", path: "/devices/1", body: body, transactionId: "0")

    // When
    let request = command.request

    // Then
    #expect(request == expected)
}

@Test func putDevicesDataFormatsLegacyBody() {
    // Given
    let command = TydomCommand.putDevicesData(deviceId: "1", endpointId: "2", name: "open", value: .bool(true), transactionId: "0")
    let body = "[{\"name\":\"open\",\"value\":true}]"
    let expected = expectedRequest(
        method: "PUT",
        path: "/devices/1/endpoints/2/data",
        body: body,
        transactionId: "0"
    )

    // When
    let request = command.request

    // Then
    #expect(request == expected)
}

@Test func alarmCDataUsesAlarmCommandWithoutZone() {
    // Given
    let commands = TydomCommand.alarmCData(
        deviceId: "10",
        endpointId: "20",
        alarmPin: "1234",
        value: "ON",
        transactionId: "0"
    )
    let body = "{\"value\":\"ON\",\"pwd\":\"1234\"}"
    let expected = expectedRequest(
        method: "PUT",
        path: "/devices/10/endpoints/20/cdata?name=alarmCmd",
        body: body,
        transactionId: "0"
    )

    // When
    let request = commands.first?.request

    // Then
    #expect(commands.count == 1)
    #expect(request == expected)
}

@Test func alarmCDataLegacyZonesSplitsCommands() {
    // Given
    let commands = TydomCommand.alarmCData(
        deviceId: "10",
        endpointId: "20",
        alarmPin: "1234",
        value: "ON",
        zoneId: "1, 2",
        legacyZones: true,
        transactionId: "0"
    )

    // When
    let requests = commands.map(\.request)

    // Then
    #expect(commands.count == 2)
    #expect(requests[0].contains("cdata?name=partCmd"))
    #expect(requests[1].contains("cdata?name=partCmd"))
    #expect(requests[0].contains("\"part\":\"1\""))
    #expect(requests[1].contains("\"part\":\"2\""))
}

@Test func ackEventsCDataUsesPutDataFormat() {
    // Given
    let command = TydomCommand.ackEventsCData(deviceId: "10", endpointId: "20", alarmPin: "9999", transactionId: "0")
    let body = "{\"pwd\":\"9999\"}"
    let expected = expectedRequest(
        method: "PUT",
        path: "/devices/10/endpoints/20/cdata?name=ackEventCmd",
        body: body,
        transactionId: "0"
    )

    // When
    let request = command.request

    // Then
    #expect(request == expected)
}

private func expectedRequest(method: String, path: String, body: String?, transactionId: String) -> String {
    let length = body?.data(using: .utf8)?.count ?? 0
    var request = "\(method) \(path) HTTP/1.1\r\nContent-Length: \(length)\r\nContent-Type: application/json; charset=UTF-8\r\nTransac-Id: \(transactionId)\r\n"
    if let body {
        request += "\r\n\(body)\r\n\r\n"
    } else {
        request += "\r\n"
    }
    return request
}
