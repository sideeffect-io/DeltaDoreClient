import Foundation

actor TydomMessageEffectExecutor {
    struct Dependencies: Sendable {
        let sendCommand: @Sendable (TydomCommand) async throws -> Void
        let pollScheduler: @Sendable ([String], Int) async -> Void
        let pollOnceScheduled: @Sendable () async -> Void
        let onPong: @Sendable () async -> Void
        let onCDataReplyChunk: @Sendable (TydomCDataReplyChunk) async -> Void
        let log: @Sendable (String) -> Void

        init(
            sendCommand: @escaping @Sendable (TydomCommand) async throws -> Void,
            pollScheduler: @escaping @Sendable ([String], Int) async -> Void,
            pollOnceScheduled: @escaping @Sendable () async -> Void = {},
            onPong: @escaping @Sendable () async -> Void = {},
            onCDataReplyChunk: @escaping @Sendable (TydomCDataReplyChunk) async -> Void = { _ in },
            log: @escaping @Sendable (String) -> Void = { _ in }
        ) {
            self.sendCommand = sendCommand
            self.pollScheduler = pollScheduler
            self.pollOnceScheduled = pollOnceScheduled
            self.onPong = onPong
            self.onCDataReplyChunk = onCDataReplyChunk
            self.log = log
        }
    }

    private let continuation: AsyncStream<TydomMessageEffect>.Continuation
    private let workerTask: Task<Void, Never>
    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        let (stream, continuation) = AsyncStream<TydomMessageEffect>.makeStream()
        self.continuation = continuation
        self.dependencies = dependencies
        self.workerTask = Task {
            for await effect in stream {
                await Self.handle(effect, dependencies: dependencies)
            }
        }
    }

    deinit {
        continuation.finish()
        workerTask.cancel()
    }

    func enqueue(_ effects: [TydomMessageEffect]) {
        for effect in effects {
            continuation.yield(effect)
        }
    }

    private static func handle(_ effect: TydomMessageEffect, dependencies: Dependencies) async {
        switch effect {
        case .sendCommands(let commands):
            for command in commands {
                _ = try? await dependencies.sendCommand(command)
            }
        case .schedulePoll(let urls, let intervalSeconds):
            await dependencies.pollScheduler(urls, intervalSeconds)
        case .refreshAll:
            _ = try? await dependencies.sendCommand(.refreshAll())
            await dependencies.pollOnceScheduled()
        case .pongReceived:
            await dependencies.onPong()
        case .cdataReplyChunk(let chunk):
            await dependencies.onCDataReplyChunk(chunk)
        }
    }
}

extension TydomMessageEffectExecutor {
    static func live(
        pollingConfiguration: TydomConnection.Configuration.Polling = .init(),
        sendCommand: @escaping @Sendable (TydomCommand) async throws -> Void,
        isActive: @escaping @Sendable () async -> Bool = { true },
        pollScheduler: TydomMessagePollScheduler? = nil,
        pongStore: TydomPongStore = TydomPongStore(),
        cdataReplyStore: TydomCDataReplyStore = TydomCDataReplyStore(),
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) -> TydomMessageEffectExecutor {
        let activeCheck: @Sendable () async -> Bool
        if pollingConfiguration.onlyWhenActive {
            activeCheck = isActive
        } else {
            activeCheck = { true }
        }
        let scheduler = pollScheduler ?? TydomMessagePollScheduler(
            send: sendCommand,
            isActive: activeCheck
        )
        let dependencies = Dependencies(
            sendCommand: sendCommand,
            pollScheduler: { urls, _ in
                let effectiveInterval = pollingConfiguration.intervalSeconds
                guard pollingConfiguration.isEnabled else {
                    log("Polling disabled (intervalSeconds=\(effectiveInterval)).")
                    return
                }
                if urls.isEmpty {
                    log("Polling schedule skipped (no urls).")
                    return
                }
                log("Polling scheduled for \(urls.count) url(s) every \(effectiveInterval)s.")
                await scheduler.schedule(urls: urls, intervalSeconds: effectiveInterval)
            },
            pollOnceScheduled: {
                log("Polling once for scheduled urls.")
                await scheduler.pollOnceScheduled()
            },
            onPong: {
                await pongStore.markPongReceived()
            },
            onCDataReplyChunk: { chunk in
                await cdataReplyStore.append(chunk)
            },
            log: log
        )
        return TydomMessageEffectExecutor(dependencies: dependencies)
    }
}
