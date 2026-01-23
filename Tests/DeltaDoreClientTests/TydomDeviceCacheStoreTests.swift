import Testing
@testable import DeltaDoreClient

@Test func tydomDeviceCacheStore_configsFilePopulatesNameAndUsage() async {
    // Given
    let cache = TydomDeviceCacheStore()
    await cache.upsert(TydomDeviceCacheEntry(uniqueId: "2_1", name: "Living Room", usage: "shutter"))
    await cache.upsert(TydomDeviceCacheEntry(uniqueId: "3_1", name: "Alarm", usage: "alarm"))

    // When
    let shutter = await cache.deviceInfo(for: "2_1")
    #expect(shutter?.name == "Living Room")
    #expect(shutter?.usage == "shutter")

    // Then
    let alarm = await cache.deviceInfo(for: "3_1")
    #expect(alarm?.name == "Alarm")
    #expect(alarm?.usage == "alarm")
}

@Test func tydomDeviceCacheStore_devicesMetaAddsMetadata() async {
    // Given
    let cache = TydomDeviceCacheStore()
    await cache.upsert(TydomDeviceCacheEntry(uniqueId: "2_1", name: "Living Room", usage: "shutter"))

    let payloadMetadata: [String: JSONValue] = [
        "position": .object(["min": .number(0), "max": .number(100)])
    ]

    // When
    await cache.upsert(TydomDeviceCacheEntry(uniqueId: "2_1", metadata: payloadMetadata))

    // Then
    let device = await cache.deviceInfo(for: "2_1")
    let storedMetadata = device?.metadata
    #expect(storedMetadata?["position"] == .object(["min": .number(0), "max": .number(100)]))
}

@Test func tydomDeviceCacheStore_devicesMetaBeforeConfigsIsRetained() async {
    // Given
    let cache = TydomDeviceCacheStore()
    let payloadMetadata: [String: JSONValue] = [
        "position": .object(["min": .number(0), "max": .number(100)])
    ]

    // When
    await cache.upsert(TydomDeviceCacheEntry(uniqueId: "2_1", metadata: payloadMetadata))

    await cache.upsert(TydomDeviceCacheEntry(uniqueId: "2_1", name: "Living Room", usage: "shutter"))

    // Then
    let device = await cache.deviceInfo(for: "2_1")
    #expect(device?.name == "Living Room")
    #expect(device?.usage == "shutter")
    #expect(device?.metadata?["position"] == .object(["min": .number(0), "max": .number(100)]))
}
