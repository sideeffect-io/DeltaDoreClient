import Foundation

struct TydomMessageHydratorDependencies: Sendable {
    let deviceInfo: @Sendable (String) async -> TydomDeviceInfo?
    let scenarioMetadata: @Sendable (Int) async -> TydomScenarioMetadata?
    let applyCacheMutation: @Sendable (TydomCacheMutation) async -> Void

    init(
        deviceInfo: @escaping @Sendable (String) async -> TydomDeviceInfo?,
        scenarioMetadata: @escaping @Sendable (Int) async -> TydomScenarioMetadata?,
        applyCacheMutation: @escaping @Sendable (TydomCacheMutation) async -> Void
    ) {
        self.deviceInfo = deviceInfo
        self.scenarioMetadata = scenarioMetadata
        self.applyCacheMutation = applyCacheMutation
    }
}

extension TydomMessageHydratorDependencies {
    static func live(
        _ cache: TydomDeviceCacheStore = TydomDeviceCacheStore(),
        scenarioStore: TydomScenarioMetadataStore = TydomScenarioMetadataStore()
    ) -> TydomMessageHydratorDependencies {
        TydomMessageHydratorDependencies(
            deviceInfo: { uniqueId in
                await cache.deviceInfo(for: uniqueId)
            },
            scenarioMetadata: { scenarioId in
                await scenarioStore.metadata(for: scenarioId)
            },
            applyCacheMutation: { mutation in
                switch mutation {
                case .deviceEntry(let entry):
                    await cache.upsert(entry)
                case .scenarioMetadata(let metadata):
                    await scenarioStore.upsert(metadata)
                }
            }
        )
    }
}

struct TydomMessageHydrator: Sendable {
    private let dependencies: TydomMessageHydratorDependencies

    init(dependencies: TydomMessageHydratorDependencies) {
        self.dependencies = dependencies
    }

    func hydrate(_ decoded: TydomDecodedEnvelope) async -> TydomHydratedEnvelope {
        for mutation in decoded.cacheMutations {
            await dependencies.applyCacheMutation(mutation)
        }

        switch decoded.payload {
        case .gatewayInfo(let info):
            return TydomHydratedEnvelope(
                message: .gatewayInfo(info, transactionId: decoded.raw.transactionId),
                effects: decoded.effects
            )
        case .deviceUpdates(let updates):
            let result = await hydrateDeviceUpdates(from: updates, transactionId: decoded.raw.transactionId)
            let devices = result.devices
            let extraEffects = result.effects
            if devices.isEmpty {
                return TydomHydratedEnvelope(
                    message: .raw(decoded.raw),
                    effects: decoded.effects + extraEffects
                )
            }
            return TydomHydratedEnvelope(
                message: .devices(devices, transactionId: decoded.raw.transactionId),
                effects: decoded.effects + extraEffects
            )
        case .scenarios(let payloads):
            let scenarios = await hydrateScenarios(from: payloads)
            if scenarios.isEmpty {
                return TydomHydratedEnvelope(message: .raw(decoded.raw), effects: decoded.effects)
            }
            return TydomHydratedEnvelope(
                message: .scenarios(scenarios, transactionId: decoded.raw.transactionId),
                effects: decoded.effects
            )
        case .groups(let groups):
            return TydomHydratedEnvelope(
                message: .groups(groups, transactionId: decoded.raw.transactionId),
                effects: decoded.effects
            )
        case .moments(let moments):
            return TydomHydratedEnvelope(
                message: .moments(moments, transactionId: decoded.raw.transactionId),
                effects: decoded.effects
            )
        case .areas(let areas):
            return TydomHydratedEnvelope(
                message: .areas(areas, transactionId: decoded.raw.transactionId),
                effects: decoded.effects
            )
        case .none:
            return TydomHydratedEnvelope(message: .raw(decoded.raw), effects: decoded.effects)
        }
    }

    private func hydrateDeviceUpdates(
        from updates: [TydomDeviceUpdate],
        transactionId: String?
    ) async -> (devices: [TydomDevice], effects: [TydomMessageEffect]) {
        var devices: [TydomDevice] = []
        var effects: [TydomMessageEffect] = []
        for update in updates {
            guard let info = await dependencies.deviceInfo(update.uniqueId) else { continue }
            if update.source == .cdata {
                if info.usage == "alarm" {
                    if let transactionId, let entries = update.cdataEntries, entries.isEmpty == false {
                        let done = entries.contains { entry in
                            entry.objectValue?["EOR"]?.boolValue == true
                        }
                        effects.append(.cdataReplyChunk(TydomCDataReplyChunk(
                            transactionId: transactionId,
                            events: entries,
                            done: done
                        )))
                    }
                    continue
                }
                if info.usage != "conso" {
                    continue
                }
                if update.data.isEmpty {
                    continue
                }
            }
            devices.append(TydomDevice(
                id: update.id,
                endpointId: update.endpointId,
                uniqueId: update.uniqueId,
                name: info.name,
                usage: info.usage,
                kind: TydomDeviceKind.fromUsage(info.usage),
                data: update.data,
                metadata: info.metadata ?? update.metadata
            ))
        }
        return (devices, effects)
    }

    private func hydrateScenarios(from payloads: [TydomScenarioPayload]) async -> [TydomScenario] {
        var scenarios: [TydomScenario] = []
        for payload in payloads {
            let metadata = await dependencies.scenarioMetadata(payload.id)
            let name = metadata?.name ?? payload.payload["name"]?.stringValue ?? "Scenario \(payload.id)"
            let type = metadata?.type ?? payload.payload["type"]?.stringValue ?? "NORMAL"
            let picto = metadata?.picto ?? payload.payload["picto"]?.stringValue ?? ""
            let ruleId = metadata?.ruleId ?? payload.payload["rule_id"]?.stringValue
            scenarios.append(TydomScenario(
                id: payload.id,
                name: name,
                type: type,
                picto: picto,
                ruleId: ruleId,
                payload: payload.payload
            ))
        }
        return scenarios
    }
}

extension TydomMessageHydrator {
    static func live(
        cache: TydomDeviceCacheStore = TydomDeviceCacheStore(),
        scenarioStore: TydomScenarioMetadataStore = TydomScenarioMetadataStore()
    ) -> TydomMessageHydrator {
        TydomMessageHydrator(dependencies: .live(cache, scenarioStore: scenarioStore))
    }
}

struct TydomHydratedEnvelope: Sendable, Equatable {
    let message: TydomMessage
    let effects: [TydomMessageEffect]

    init(message: TydomMessage, effects: [TydomMessageEffect] = []) {
        self.message = message
        self.effects = effects
    }
}
