import Foundation

extension TydomConnection {
    public func decodedMessages() -> AsyncStream<TydomMessage> {
        decodedMessages(logger: { _ in })
    }

    public func decodedMessages(
        logger: @escaping @Sendable (String) -> Void
    ) -> AsyncStream<TydomMessage> {
        let dependencies = TydomMessagePipelineDependencies.live(connection: self, log: logger)
        return AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                for await data in await self.messages() {
                    let raw = dependencies.dataToRawMessage(data)
                    let decoded = dependencies.rawMessageToEnvelope(raw)
                    let hydrated = await dependencies.hydrateFromCache(decoded)
                    Task { await dependencies.enqueueEffects(hydrated.effects) }
                    continuation.yield(hydrated.message)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
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
        log: @escaping @Sendable (String) -> Void = { _ in }
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
            cdataReplyStore: TydomCDataReplyStore(),
            log: log
        )
        
        return live(hydrator: hydrator, effectExecutor: effectExecutor)
    }
}
