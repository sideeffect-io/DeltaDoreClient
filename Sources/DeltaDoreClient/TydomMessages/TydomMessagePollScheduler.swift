import Foundation

actor TydomMessagePollScheduler {
    struct Entry: Hashable, Sendable {
        let url: String
        let intervalSeconds: Int

        init(url: String, intervalSeconds: Int) {
            self.url = url
            self.intervalSeconds = intervalSeconds
        }
    }

    private let send: @Sendable (TydomCommand) async throws -> Void
    private let isActive: @Sendable () async -> Bool
    private var tasks: [Entry: Task<Void, Never>] = [:]

    init(
        send: @escaping @Sendable (TydomCommand) async throws -> Void,
        isActive: @escaping @Sendable () async -> Bool = { true }
    ) {
        self.send = send
        self.isActive = isActive
    }

    deinit {
        for task in tasks.values {
            task.cancel()
        }
    }

    func schedule(urls: [String], intervalSeconds: Int) {
        guard intervalSeconds > 0 else { return }
        for url in urls {
            let entry = Entry(url: url, intervalSeconds: intervalSeconds)
            guard tasks[entry] == nil else { continue }
            tasks[entry] = makeTask(for: entry)
        }
    }

    func pollOnceScheduled() async {
        guard await isActive() else { return }
        let entries = Array(tasks.keys)
        for entry in entries {
            _ = try? await send(TydomCommand.pollDeviceData(url: entry.url))
        }
    }

    func cancel(urls: [String], intervalSeconds: Int) {
        for url in urls {
            let entry = Entry(url: url, intervalSeconds: intervalSeconds)
            if let task = tasks.removeValue(forKey: entry) {
                task.cancel()
            }
        }
    }

    private func makeTask(for entry: Entry) -> Task<Void, Never> {
        Task { [send] in
            let sleepNanoseconds = UInt64(entry.intervalSeconds) * 1_000_000_000
            while !Task.isCancelled {
                if await isActive() {
                    do {
                        try await send(TydomCommand.pollDeviceData(url: entry.url))
                    } catch {
                    }
                }
                do {
                    try await Task.sleep(nanoseconds: sleepNanoseconds)
                } catch {
                    break
                }
            }
        }
    }
}
