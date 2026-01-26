import Foundation
import Testing
@testable import DeltaDoreClient

@Test func gatewayDiscovery_includesCachedIPFirst() async {
    // Given
    let dependencies = TydomGatewayDiscovery.Dependencies(
        discoverBonjour: { _, _ in [] },
        subnetHosts: { [] },
        probeHost: { _, _, _ in false }
    )
    let discovery = TydomGatewayDiscovery(dependencies: dependencies)
    let config = TydomGatewayDiscoveryConfig()

    // When
    let candidates = await discovery.discover(
        mac: "AA:BB:CC:DD:EE:FF",
        cachedIP: "192.168.1.20",
        config: config
    )

    // Then
    #expect(candidates.first?.host == "192.168.1.20")
    #expect(candidates.first?.method == .cachedIP)
}
