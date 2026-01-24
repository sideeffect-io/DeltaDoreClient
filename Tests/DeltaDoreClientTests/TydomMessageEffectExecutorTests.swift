import Foundation
import Testing
@testable import DeltaDoreClient

@Test func tydomMessageEffectExecutor_executesEffectsInOrder() async {
    // Given
    let probe = EffectProbe()
    let executor = TydomMessageEffectExecutor(dependencies: .testDependencies(probe: probe))
    let chunk = TydomCDataReplyChunk(transactionId: "t1", events: [.string("ok")], done: true)

    // When
    await executor.enqueue([
        .sendCommands([TydomCommand(request: "A"), TydomCommand(request: "B")]),
        .schedulePoll(urls: ["/a"], intervalSeconds: 30),
        .pongReceived,
        .cdataReplyChunk(chunk)
    ])

    let values = await probe.nextValues(count: 5)

    // Then
    #expect(values == [
        "send:A",
        "send:B",
        "poll:/a:30",
        "pong",
        "cdata:t1"
    ])
}

@Test func tydomMessageEffectExecutor_cancelsWorkerOnDeinit() async {
    // Given
    let (blockStream, blockContinuation) = AsyncStream<Void>.makeStream()
    let (startedStream, startedContinuation) = AsyncStream<Void>.makeStream()
    let (cancelStream, cancelContinuation) = AsyncStream<Void>.makeStream()

    var executor: TydomMessageEffectExecutor? = TydomMessageEffectExecutor(
        dependencies: .init(
            sendCommand: { _ in
                startedContinuation.yield(())
                await withTaskCancellationHandler(operation: {
                    var iterator = blockStream.makeAsyncIterator()
                    _ = await iterator.next()
                }, onCancel: {
                    cancelContinuation.yield(())
                })
            },
            pollScheduler: { _, _ in },
            pollOnceScheduled: {},
            onPong: {},
            onCDataReplyChunk: { _ in }
        )
    )

    // When
    await executor?.enqueue([.refreshAll])
    var startedIterator = startedStream.makeAsyncIterator()
    _ = await startedIterator.next()
    executor = nil
    blockContinuation.finish()

    // Then
    var cancelIterator = cancelStream.makeAsyncIterator()
    _ = await cancelIterator.next()
    #expect(Bool(true))
}

@Test func tydomMessageEffectExecutor_doesNotBlockMapChain() async {
    // Given
    let (blockStream, blockContinuation) = AsyncStream<Void>.makeStream()
    let executor = TydomMessageEffectExecutor(
        dependencies: .init(
            sendCommand: { _ in
                var iterator = blockStream.makeAsyncIterator()
                _ = await iterator.next()
            },
            pollScheduler: { _, _ in },
            pollOnceScheduled: {},
            onPong: {},
            onCDataReplyChunk: { _ in }
        )
    )

    let (input, continuation) = AsyncStream<Int>.makeStream()
    let output = input
        .map { value in (message: value, effects: [TydomMessageEffect.refreshAll]) }
        .map { hydrated in
            Task { await executor.enqueue(hydrated.effects) }
            return hydrated.message
        }

    // When
    continuation.yield(42)

    let value: Int? = await withTaskGroup(of: Int?.self) { group -> Int? in
        group.addTask {
            var localIterator = output.makeAsyncIterator()
            return await localIterator.next()
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: 200_000_000)
            return nil
        }
        for await result in group {
            if let result { return result }
        }
        return nil
    }

    // Then
    #expect(value == 42)
    blockContinuation.finish()
}

private actor EffectProbe {
    private var received: [String] = []
    private let stream: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation

    init() {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    func record(_ value: String) {
        received.append(value)
        continuation.yield(value)
    }

    func nextValues(count: Int) async -> [String] {
        var iterator = stream.makeAsyncIterator()
        var values: [String] = []
        for _ in 0..<count {
            if let next = await iterator.next() {
                values.append(next)
            }
        }
        return values
    }
}

private extension TydomMessageEffectExecutor.Dependencies {
    static func testDependencies(probe: EffectProbe) -> TydomMessageEffectExecutor.Dependencies {
        TydomMessageEffectExecutor.Dependencies(
            sendCommand: { command in
                await probe.record("send:\(command.request)")
            },
            pollScheduler: { urls, interval in
                let urlList = urls.joined(separator: ",")
                await probe.record("poll:\(urlList):\(interval)")
            },
            pollOnceScheduled: {
                await probe.record("pollOnce")
            },
            onPong: {
                await probe.record("pong")
            },
            onCDataReplyChunk: { chunk in
                await probe.record("cdata:\(chunk.transactionId)")
            }
        )
    }
}
