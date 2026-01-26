import Foundation

public struct TydomConnectionState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case idle
        case loadingSiteList
        case selectingSite
        case loadingCredentials
        case tryingCachedIP
        case discoveringLocal
        case connectingLocal
        case connectingRemote
        case connected
        case failed
    }

    public enum ModeOverride: Sendable, Equatable {
        case none
        case forceLocal
        case forceRemote
    }

    public struct Decision: Sendable, Equatable {
        public enum Reason: String, Sendable, Equatable {
            case missingCredentials
            case overrideLocal
            case overrideRemote
            case cachedIPFailed
            case localDiscoveryFailed
            case localConnected
            case remoteConnected
            case localFailed
            case remoteFailed
        }

        public let mode: TydomConnection.Configuration.Mode
        public let reason: Reason
    }

    public let phase: Phase
    public let override: ModeOverride
    public let credentials: TydomGatewayCredentials?
    public let selectedGatewayMac: String?
    public let lastDecision: Decision?
    public let lastError: String?

    public init(
        phase: Phase = .idle,
        override: ModeOverride = .none,
        credentials: TydomGatewayCredentials? = nil,
        selectedGatewayMac: String? = nil,
        lastDecision: Decision? = nil,
        lastError: String? = nil
    ) {
        self.phase = phase
        self.override = override
        self.credentials = credentials
        self.selectedGatewayMac = selectedGatewayMac
        self.lastDecision = lastDecision
        self.lastError = lastError
    }
}

public enum TydomConnectionEvent: Sendable, Equatable {
    case start
    case overrideLocal
    case overrideRemote
    case clearOverride
    case credentialsLoaded(TydomGatewayCredentials?)
    case credentialsSaved(TydomGatewayCredentials)
    case cachedIPFailed
    case localDiscoveryFound([TydomLocalGateway])
    case localConnectResult(success: Bool, host: String?)
    case remoteConnectResult(success: Bool)
    case failure(String)
}

public enum TydomConnectionAction: Sendable, Equatable {
    case loadCredentials
    case saveCredentials(TydomGatewayCredentials)
    case tryCachedIP(String)
    case discoverLocal
    case connectLocal(String)
    case connectRemote
    case emitDecision(TydomConnectionState.Decision)
}

public struct TydomConnectionStateMachine {
    public static func reduce(
        state: TydomConnectionState,
        event: TydomConnectionEvent
    ) -> (TydomConnectionState, [TydomConnectionAction]) {
        switch event {
        case .start:
            return (
                TydomConnectionState(
                    phase: .loadingCredentials,
                    override: state.override,
                    credentials: state.credentials,
                    selectedGatewayMac: state.selectedGatewayMac,
                    lastDecision: state.lastDecision,
                    lastError: nil
                ),
                [.loadCredentials]
            )

        case .overrideLocal:
            let next = TydomConnectionState(
                phase: state.phase,
                override: .forceLocal,
                credentials: state.credentials,
                selectedGatewayMac: state.selectedGatewayMac,
                lastDecision: state.lastDecision,
                lastError: nil
            )
            return (next, [])

        case .overrideRemote:
            let next = TydomConnectionState(
                phase: state.phase,
                override: .forceRemote,
                credentials: state.credentials,
                selectedGatewayMac: state.selectedGatewayMac,
                lastDecision: state.lastDecision,
                lastError: nil
            )
            return (next, [.connectRemote])

        case .clearOverride:
            let next = TydomConnectionState(
                phase: state.phase,
                override: .none,
                credentials: state.credentials,
                selectedGatewayMac: state.selectedGatewayMac,
                lastDecision: state.lastDecision,
                lastError: nil
            )
            return (next, [])

        case .credentialsLoaded(let credentials):
            guard let credentials else {
                let decision = TydomConnectionState.Decision(
                    mode: .remote(),
                    reason: .missingCredentials
                )
                return (
                    TydomConnectionState(
                        phase: .connectingRemote,
                        override: state.override,
                        credentials: nil,
                        selectedGatewayMac: state.selectedGatewayMac,
                        lastDecision: decision,
                        lastError: nil
                    ),
                    [.emitDecision(decision), .connectRemote]
                )
            }

            if state.override == .forceRemote {
                let decision = TydomConnectionState.Decision(
                    mode: .remote(),
                    reason: .overrideRemote
                )
                return (
                    TydomConnectionState(
                        phase: .connectingRemote,
                        override: state.override,
                        credentials: credentials,
                        selectedGatewayMac: credentials.mac,
                        lastDecision: decision,
                        lastError: nil
                    ),
                    [.emitDecision(decision), .connectRemote]
                )
            }

            if state.override == .forceLocal {
                let decision = TydomConnectionState.Decision(
                    mode: .local(host: credentials.cachedLocalIP ?? ""),
                    reason: .overrideLocal
                )
                if let cached = credentials.cachedLocalIP, cached.isEmpty == false {
                    return (
                        TydomConnectionState(
                            phase: .tryingCachedIP,
                            override: state.override,
                            credentials: credentials,
                            selectedGatewayMac: credentials.mac,
                            lastDecision: decision,
                            lastError: nil
                        ),
                        [.emitDecision(decision), .tryCachedIP(cached)]
                    )
                }
                return (
                    TydomConnectionState(
                        phase: .discoveringLocal,
                        override: state.override,
                        credentials: credentials,
                        selectedGatewayMac: credentials.mac,
                        lastDecision: decision,
                        lastError: nil
                    ),
                    [.emitDecision(decision), .discoverLocal]
                )
            }

            if let cached = credentials.cachedLocalIP, cached.isEmpty == false {
                let decision = TydomConnectionState.Decision(
                    mode: .local(host: cached),
                    reason: .localConnected
                )
                return (
                    TydomConnectionState(
                        phase: .tryingCachedIP,
                        override: state.override,
                        credentials: credentials,
                        selectedGatewayMac: credentials.mac,
                        lastDecision: decision,
                        lastError: nil
                    ),
                    [.emitDecision(decision), .tryCachedIP(cached)]
                )
            }

            return (
                TydomConnectionState(
                    phase: .discoveringLocal,
                    override: state.override,
                    credentials: credentials,
                    selectedGatewayMac: credentials.mac,
                    lastDecision: state.lastDecision,
                    lastError: nil
                ),
                [.discoverLocal]
            )

        case .cachedIPFailed:
            guard let credentials = state.credentials else {
                let decision = TydomConnectionState.Decision(
                    mode: .remote(),
                    reason: .missingCredentials
                )
                return (
                    TydomConnectionState(
                        phase: .connectingRemote,
                        override: state.override,
                        credentials: nil,
                        selectedGatewayMac: state.selectedGatewayMac,
                        lastDecision: decision,
                        lastError: nil
                    ),
                    [.emitDecision(decision), .connectRemote]
                )
            }
            return (
                TydomConnectionState(
                    phase: .discoveringLocal,
                    override: state.override,
                    credentials: credentials,
                    selectedGatewayMac: credentials.mac,
                    lastDecision: state.lastDecision,
                    lastError: nil
                ),
                [.discoverLocal]
            )

        case .localDiscoveryFound(let candidates):
            guard let credentials = state.credentials else {
                let decision = TydomConnectionState.Decision(
                    mode: .remote(),
                    reason: .missingCredentials
                )
                return (
                    TydomConnectionState(
                        phase: .connectingRemote,
                        override: state.override,
                        credentials: nil,
                        selectedGatewayMac: state.selectedGatewayMac,
                        lastDecision: decision,
                        lastError: nil
                    ),
                    [.emitDecision(decision), .connectRemote]
                )
            }

            guard let first = candidates.first else {
                let decision = TydomConnectionState.Decision(
                    mode: .remote(),
                    reason: .localDiscoveryFailed
                )
                return (
                    TydomConnectionState(
                        phase: .connectingRemote,
                        override: state.override,
                        credentials: credentials,
                        selectedGatewayMac: credentials.mac,
                        lastDecision: decision,
                        lastError: nil
                    ),
                    [.emitDecision(decision), .connectRemote]
                )
            }

            let decision = TydomConnectionState.Decision(
                mode: .local(host: first.host),
                reason: .localConnected
            )
            return (
                TydomConnectionState(
                    phase: .connectingLocal,
                    override: state.override,
                    credentials: credentials,
                    selectedGatewayMac: credentials.mac,
                    lastDecision: decision,
                    lastError: nil
                ),
                [.emitDecision(decision), .connectLocal(first.host)]
            )

        case .localConnectResult(let success, let host):
            if success, let host {
                guard let credentials = state.credentials else {
                    return (
                        TydomConnectionState(
                            phase: .connected,
                            override: state.override,
                            credentials: state.credentials,
                            selectedGatewayMac: state.selectedGatewayMac,
                            lastDecision: state.lastDecision,
                            lastError: nil
                        ),
                        []
                    )
                }
                let updated = TydomGatewayCredentials(
                    mac: credentials.mac,
                    password: credentials.password,
                    cachedLocalIP: host,
                    updatedAt: credentials.updatedAt
                )
                return (
                    TydomConnectionState(
                        phase: .connected,
                        override: state.override,
                        credentials: updated,
                        selectedGatewayMac: credentials.mac,
                        lastDecision: state.lastDecision,
                        lastError: nil
                    ),
                    [.saveCredentials(updated)]
                )
            }

            let decision = TydomConnectionState.Decision(
                mode: .remote(),
                reason: .localFailed
            )
            return (
                TydomConnectionState(
                    phase: .connectingRemote,
                    override: state.override,
                    credentials: state.credentials,
                    selectedGatewayMac: state.selectedGatewayMac,
                    lastDecision: decision,
                    lastError: nil
                ),
                [.emitDecision(decision), .connectRemote]
            )

        case .remoteConnectResult(let success):
            if success {
                return (
                    TydomConnectionState(
                        phase: .connected,
                        override: state.override,
                        credentials: state.credentials,
                        selectedGatewayMac: state.selectedGatewayMac,
                        lastDecision: state.lastDecision,
                        lastError: nil
                    ),
                    []
                )
            }
            let decision = TydomConnectionState.Decision(
                mode: .remote(),
                reason: .remoteFailed
            )
            return (
                TydomConnectionState(
                    phase: .failed,
                    override: state.override,
                    credentials: state.credentials,
                    selectedGatewayMac: state.selectedGatewayMac,
                    lastDecision: decision,
                    lastError: "Remote connection failed"
                ),
                [.emitDecision(decision)]
            )

        case .credentialsSaved(let credentials):
            return (
                TydomConnectionState(
                    phase: state.phase,
                    override: state.override,
                    credentials: credentials,
                    selectedGatewayMac: credentials.mac,
                    lastDecision: state.lastDecision,
                    lastError: nil
                ),
                []
            )

        case .failure(let message):
            return (
                TydomConnectionState(
                    phase: .failed,
                    override: state.override,
                    credentials: state.credentials,
                    selectedGatewayMac: state.selectedGatewayMac,
                    lastDecision: state.lastDecision,
                    lastError: message
                ),
                []
            )
        }
    }
}
