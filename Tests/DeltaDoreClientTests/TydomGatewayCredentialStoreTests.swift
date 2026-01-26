import Foundation
import Testing
@testable import DeltaDoreClient

@Test func credentialStore_saveLoadDelete() async throws {
    // Given
    let store = TydomGatewayCredentialStore.inMemory()
    let credentials = TydomGatewayCredentials(
        mac: "AA:BB:CC:DD:EE:FF",
        password: "secret",
        cachedLocalIP: "192.168.1.11",
        updatedAt: Date()
    )

    // When
    try await store.save("gateway-1", credentials)
    let loaded = try await store.load("gateway-1")
    try await store.delete("gateway-1")
    let deleted = try await store.load("gateway-1")

    // Then
    #expect(loaded == credentials)
    #expect(deleted == nil)
}
