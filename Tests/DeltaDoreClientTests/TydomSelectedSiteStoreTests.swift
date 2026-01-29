import Foundation
import Testing
@testable import DeltaDoreClient

@Test func selectedSiteStore_saveLoadDelete() async throws {
    // Given
    let store = TydomSelectedSiteStore.inMemory()
    let site = TydomSelectedSite(id: "site-1", name: "Home", gatewayMac: "aa:bb:cc:dd:ee:ff")

    // When
    try await store.save("default", site)
    let loaded = try await store.load("default")
    try await store.delete("default")
    let deleted = try await store.load("default")

    // Then
    #expect(loaded == site)
    #expect(deleted == nil)
}

@Test func selectedSite_normalizesMac() async throws {
    // Given
    let site = TydomSelectedSite(id: "site-1", name: "Home", gatewayMac: "aa:bb:cc:dd:ee:ff")

    // When
    let normalized = site.gatewayMac

    // Then
    #expect(normalized == "AABBCCDDEEFF")
}
