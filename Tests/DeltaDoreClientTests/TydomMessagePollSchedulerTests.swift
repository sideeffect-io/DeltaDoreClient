import Foundation
import Testing
@testable import DeltaDoreClient

@Test func pollScheduler_pollOnceScheduledSendsWhenActive() async {
    // Given
    let recorder = CommandRecorder()
    let activity = ActivityFlag(initial: true)
    let scheduler = TydomMessagePollScheduler(
        send: { command in await recorder.record(command) },
        isActive: { await activity.isActive() }
    )

    // When
    await scheduler.schedule(urls: ["/a", "/b"], intervalSeconds: 60)
    try? await Task.sleep(nanoseconds: 50_000_000)
    let initialCount = await recorder.count()

    await scheduler.pollOnceScheduled()
    try? await Task.sleep(nanoseconds: 50_000_000)
    let afterCount = await recorder.count()

    // Then
    #expect(initialCount >= 2)
    #expect(afterCount >= initialCount + 2)
}

@Test func pollScheduler_respectsInactiveFlag() async {
    // Given
    let recorder = CommandRecorder()
    let activity = ActivityFlag(initial: false)
    let scheduler = TydomMessagePollScheduler(
        send: { command in await recorder.record(command) },
        isActive: { await activity.isActive() }
    )

    // When
    await scheduler.schedule(urls: ["/a"], intervalSeconds: 60)
    try? await Task.sleep(nanoseconds: 50_000_000)
    let scheduledCount = await recorder.count()

    await scheduler.pollOnceScheduled()
    try? await Task.sleep(nanoseconds: 50_000_000)
    let afterCount = await recorder.count()

    // Then
    #expect(scheduledCount == 0)
    #expect(afterCount == 0)
}

private actor CommandRecorder {
    private var commands: [TydomCommand] = []

    func record(_ command: TydomCommand) {
        commands.append(command)
    }

    func count() -> Int {
        commands.count
    }
}

private actor ActivityFlag {
    private var value: Bool

    init(initial: Bool) {
        self.value = initial
    }

    func isActive() -> Bool {
        value
    }
}
