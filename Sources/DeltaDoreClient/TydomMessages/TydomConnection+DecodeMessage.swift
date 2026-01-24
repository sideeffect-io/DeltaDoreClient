import Foundation

extension TydomConnection {
    func decodedMessages(
        using dependencies: TydomMessagePipelineDependencies
    ) -> some AsyncSequence<TydomMessage, Never> {
        messages()
            .map(dependencies.dataToRawMessage)
            .map(dependencies.rawMessageToEnvelope)
            .map(dependencies.hydrateFromCache)
            .map { hydrated in
                Task { await dependencies.enqueueEffects(hydrated.effects) }
                return hydrated.message
            }
    }
    
    public func decodedMessages() -> some AsyncSequence<TydomMessage, Never> {
        let dependencies = TydomMessagePipelineDependencies.live(connection: self)
        
        return messages()
            .map(dependencies.dataToRawMessage)
            .map(dependencies.rawMessageToEnvelope)
            .map(dependencies.hydrateFromCache)
            .map { hydrated in
                Task { await dependencies.enqueueEffects(hydrated.effects) }
                return hydrated.message
            }
    }
}

struct TydomMessagePipelineDependencies: Sendable {
    let dataToRawMessage: @Sendable (Data) -> TydomRawMessage
    let rawMessageToEnvelope: @Sendable (TydomRawMessage) -> TydomDecodedEnvelope
    let hydrateFromCache: @Sendable (TydomDecodedEnvelope) async -> TydomHydratedEnvelope
    let enqueueEffects: @Sendable ([TydomMessageEffect]) async -> Void

    init(
        dataToRawMessage: @escaping @Sendable (Data) -> TydomRawMessage,
        rawMessageToEnvelope: @escaping @Sendable (TydomRawMessage) -> TydomDecodedEnvelope,
        hydrateFromCache: @escaping @Sendable (TydomDecodedEnvelope) async -> TydomHydratedEnvelope,
        enqueueEffects: @escaping @Sendable ([TydomMessageEffect]) async -> Void
    ) {
        self.dataToRawMessage = dataToRawMessage
        self.rawMessageToEnvelope = rawMessageToEnvelope
        self.hydrateFromCache = hydrateFromCache
        self.enqueueEffects = enqueueEffects
    }
}

extension TydomMessagePipelineDependencies {
    static func live(
        hydrator: TydomMessageHydrator = .live(),
        effectExecutor: TydomMessageEffectExecutor
    ) -> TydomMessagePipelineDependencies {
        TydomMessagePipelineDependencies(
            dataToRawMessage: { data in
                TydomRawMessageParser.parse(data)
            },
            rawMessageToEnvelope: { raw in
                TydomMessageDecoder.decode(raw)
            },
            hydrateFromCache: { decoded in
                await hydrator.hydrate(decoded)
            },
            enqueueEffects: { effects in
                await effectExecutor.enqueue(effects)
            }
        )
    }

    static func live(
        connection: TydomConnection,
    ) -> TydomMessagePipelineDependencies {
        let hydrator: TydomMessageHydrator = .live()
        
        let pollScheduler = TydomMessagePollScheduler { [weak connection] command in
            guard let connection else { return }
            try await connection.send(command)
        } isActive: {
            [weak connection] in
            await connection?.isAppActive() ?? false
        }

        let effectExecutor = TydomMessageEffectExecutor.live(
            pollingConfiguration: connection.configuration.polling,
            sendCommand: { [weak connection] command in
                guard let connection else { return }
                try await connection.send(command)
            },
            isActive: { [weak connection] in
                await connection?.isAppActive() ?? false
            },
            pollScheduler: pollScheduler,
            pongStore: TydomPongStore(),
            cdataReplyStore: TydomCDataReplyStore()
        )
        
        return live(hydrator: hydrator, effectExecutor: effectExecutor)
    }
}
