import Foundation
import Testing
@testable import DeltaDoreClient

@Test func deltaDoreClient_makeConnectionUsesResolution() async throws {
    // Given
    let configuration = TydomConnection.Configuration(
        mode: .local(host: "192.168.1.10"),
        mac: "AA:BB:CC:DD:EE:FF",
        password: "pass"
    )
    let credentials = TydomGatewayCredentials(
        mac: "AA:BB:CC:DD:EE:FF",
        password: "pass",
        cachedLocalIP: "192.168.1.10",
        updatedAt: Date()
    )
    let resolution = TydomConnectionResolver.Resolution(
        configuration: configuration,
        credentials: credentials,
        selectedSite: nil,
        decision: nil,
        onDisconnect: nil
    )
    let (stream, continuation) = AsyncStream<TydomConnectionResolver.Resolution>.makeStream()
    let dependencies = DeltaDoreClient.Dependencies(
        resolve: { _, _ in resolution },
        listSites: { _ in [] },
        listSitesPayload: { _ in Data() },
        resetSelectedSite: { _ in },
        makeConnection: { captured in
            continuation.yield(captured)
            continuation.finish()
            return TydomConnection(
                configuration: captured.configuration,
                onDisconnect: captured.onDisconnect
            )
        },
        connect: { _ in }
    )
    let client = DeltaDoreClient(dependencies: dependencies)
    let options = DeltaDoreClient.Options(mode: .auto)

    // When
    let session = try await client.makeConnection(options: options)

    // Then
    var iterator = stream.makeAsyncIterator()
    let captured = await iterator.next()
    #expect(captured?.credentials.mac == credentials.mac)
    let sessionConfig = await session.connection.configuration
    #expect(sessionConfig.host == configuration.host)
    #expect(session.resolution.credentials.mac == credentials.mac)
}

@Test func deltaDoreClient_connectInvokesConnector() async throws {
    // Given
    let configuration = TydomConnection.Configuration(
        mode: .remote(host: "mediation.tydom.com"),
        mac: "AA:BB:CC:DD:EE:FF",
        password: "pass"
    )
    let credentials = TydomGatewayCredentials(
        mac: "AA:BB:CC:DD:EE:FF",
        password: "pass",
        cachedLocalIP: nil,
        updatedAt: Date()
    )
    let resolution = TydomConnectionResolver.Resolution(
        configuration: configuration,
        credentials: credentials,
        selectedSite: nil,
        decision: nil,
        onDisconnect: nil
    )
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    let dependencies = DeltaDoreClient.Dependencies(
        resolve: { _, _ in resolution },
        listSites: { _ in [] },
        listSitesPayload: { _ in Data() },
        resetSelectedSite: { _ in },
        makeConnection: { resolved in
            TydomConnection(
                configuration: resolved.configuration,
                onDisconnect: resolved.onDisconnect
            )
        },
        connect: { _ in
            continuation.yield(())
            continuation.finish()
        }
    )
    let client = DeltaDoreClient(dependencies: dependencies)
    let options = DeltaDoreClient.Options(mode: .auto)

    // When
    _ = try await client.connect(options: options)

    // Then
    var iterator = stream.makeAsyncIterator()
    let signal: Void? = await iterator.next()
    #expect(signal != nil)
}
