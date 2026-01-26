import Foundation
import Testing
@testable import DeltaDoreClient

@Test func stateMachine_missingCredentialsForcesRemote() async {
    // Given
    let state = TydomConnectionState(phase: .idle, override: .none, credentials: nil)

    // When
    let (next, actions) = TydomConnectionStateMachine.reduce(
        state: state,
        event: .credentialsLoaded(nil)
    )

    // Then
    #expect(next.phase == .connectingRemote)
    #expect(actions.contains(.connectRemote))
}

@Test func stateMachine_cachedIPFailureTriggersDiscovery() async {
    // Given
    let credentials = TydomGatewayCredentials(
        mac: "AABBCCDDEEFF",
        password: "pass",
        cachedLocalIP: "192.168.1.10",
        updatedAt: Date()
    )
    let state = TydomConnectionState(phase: .tryingCachedIP, override: .none, credentials: credentials)

    // When
    let (next, actions) = TydomConnectionStateMachine.reduce(
        state: state,
        event: .cachedIPFailed
    )

    // Then
    #expect(next.phase == .discoveringLocal)
    #expect(actions.contains(.discoverLocal))
}

@Test func stateMachine_localFailureFallsBackToRemote() async {
    // Given
    let credentials = TydomGatewayCredentials(
        mac: "AABBCCDDEEFF",
        password: "pass",
        cachedLocalIP: "192.168.1.10",
        updatedAt: Date()
    )
    let state = TydomConnectionState(phase: .connectingLocal, override: .none, credentials: credentials)

    // When
    let (next, actions) = TydomConnectionStateMachine.reduce(
        state: state,
        event: .localConnectResult(success: false, host: nil)
    )

    // Then
    #expect(next.phase == .connectingRemote)
    #expect(actions.contains(.connectRemote))
}

@Test func stateMachine_overrideRemoteForcesRemote() async {
    // Given
    let credentials = TydomGatewayCredentials(
        mac: "AABBCCDDEEFF",
        password: "pass",
        cachedLocalIP: "192.168.1.10",
        updatedAt: Date()
    )
    let state = TydomConnectionState(phase: .loadingCredentials, override: .forceRemote, credentials: credentials)

    // When
    let (next, actions) = TydomConnectionStateMachine.reduce(
        state: state,
        event: .credentialsLoaded(credentials)
    )

    // Then
    #expect(next.phase == .connectingRemote)
    #expect(actions.contains(.connectRemote))
}

@Test func stateMachine_overrideLocalUsesDiscoveryWhenNoCache() async {
    // Given
    let credentials = TydomGatewayCredentials(
        mac: "AABBCCDDEEFF",
        password: "pass",
        cachedLocalIP: nil,
        updatedAt: Date()
    )
    let state = TydomConnectionState(phase: .loadingCredentials, override: .forceLocal, credentials: credentials)

    // When
    let (next, actions) = TydomConnectionStateMachine.reduce(
        state: state,
        event: .credentialsLoaded(credentials)
    )

    // Then
    #expect(next.phase == .discoveringLocal)
    #expect(actions.contains(.discoverLocal))
}
