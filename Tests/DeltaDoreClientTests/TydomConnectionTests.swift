import Foundation
import Testing

@testable import DeltaDoreClient

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test func configurationForRemoteUsesPrefixAndHost() {
    let config = TydomConnection.Configuration(
        mode: .remote(),
        mac: "AA:BB:CC:DD:EE:FF",
        password: "password"
    )

    #expect(config.commandPrefix == 0x02)
    #expect(config.host == "mediation.tydom.com")
    #expect(config.isRemote)
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test func configurationForLocalHasNoPrefix() {
    let config = TydomConnection.Configuration(
        mode: .local(host: "example.local"),
        mac: "AA:BB:CC:DD:EE:FF",
        password: "password"
    )

    #expect(config.commandPrefix == nil)
    #expect(config.host == "example.local")
    #expect(config.isRemote == false)
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test func sendWithoutConnectionThrows() async {
    let connection = TydomConnection(
        configuration: .init(
            mode: .local(host: "example.local"),
            mac: "AA:BB:CC:DD:EE:FF",
            password: "password"
        )
    )

    await #expect(throws: TydomConnection.ConnectionError.notConnected) {
        try await connection.send(Data())
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test func connectMissingCredentialsThrowsAndStillCreatesSession() async {
    let recorder = CallRecorder()
    let dependencies = TydomConnection.Dependencies(
        makeSession: { _, _ in
            recorder.increment("makeSession")
            return URLSession(configuration: .ephemeral)
        },
        randomBytes: { _ in [0] },
        now: { Date() },
        fetchGatewayPassword: { _, _, _ in
            recorder.increment("fetchGatewayPassword")
            throw TestError.fetchFailed
        },
        invalidateSession: { _ in
            recorder.increment("invalidateSession")
        }
    )

    let connection = TydomConnection(
        configuration: .init(
            mode: .local(host: "example.local"),
            mac: "AA:BB:CC:DD:EE:FF"
        ),
        dependencies: dependencies
    )

    await #expect(throws: TydomConnection.ConnectionError.missingCredentials) {
        try await connection.connect()
    }

    #expect(recorder.value("makeSession") == 1)
    #expect(recorder.value("fetchGatewayPassword") == 0)
    #expect(recorder.value("invalidateSession") == 0)
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test func connectPropagatesGatewayPasswordError() async {
    let recorder = CallRecorder()
    let dependencies = TydomConnection.Dependencies(
        makeSession: { _, _ in
            recorder.increment("makeSession")
            return URLSession(configuration: .ephemeral)
        },
        randomBytes: { _ in [0] },
        now: { Date() },
        fetchGatewayPassword: { _, _, _ in
            recorder.increment("fetchGatewayPassword")
            throw TestError.fetchFailed
        },
        invalidateSession: { _ in
            recorder.increment("invalidateSession")
        }
    )

    let connection = TydomConnection(
        configuration: .init(
            mode: .local(host: "example.local"),
            mac: "AA:BB:CC:DD:EE:FF",
            cloudCredentials: .init(email: "user@example.com", password: "secret")
        ),
        dependencies: dependencies
    )

    await #expect(throws: TestError.fetchFailed) {
        try await connection.connect()
    }

    #expect(recorder.value("makeSession") == 1)
    #expect(recorder.value("fetchGatewayPassword") == 1)
    #expect(recorder.value("invalidateSession") == 0)
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test func disconnectInvalidatesSessionAfterFailedConnect() async {
    let recorder = CallRecorder()
    let dependencies = TydomConnection.Dependencies(
        makeSession: { _, _ in
            recorder.increment("makeSession")
            return URLSession(configuration: .ephemeral)
        },
        randomBytes: { _ in [0] },
        now: { Date() },
        fetchGatewayPassword: { _, _, _ in
            recorder.increment("fetchGatewayPassword")
            throw TestError.fetchFailed
        },
        invalidateSession: { _ in
            recorder.increment("invalidateSession")
        }
    )

    let connection = TydomConnection(
        configuration: .init(
            mode: .local(host: "example.local"),
            mac: "AA:BB:CC:DD:EE:FF"
        ),
        dependencies: dependencies
    )

    await #expect(throws: TydomConnection.ConnectionError.missingCredentials) {
        try await connection.connect()
    }

    await connection.disconnect()

    #expect(recorder.value("invalidateSession") == 1)
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
@Test func deinitInvalidatesSession() async {
    let recorder = CallRecorder()
    let dependencies = TydomConnection.Dependencies(
        makeSession: { _, _ in
            recorder.increment("makeSession")
            return URLSession(configuration: .ephemeral)
        },
        randomBytes: { _ in [0] },
        now: { Date() },
        fetchGatewayPassword: { _, _, _ in
            throw TestError.fetchFailed
        },
        invalidateSession: { _ in
            recorder.increment("invalidateSession")
        }
    )

    weak var weakConnection: TydomConnection?

    do {
        let connection = TydomConnection(
            configuration: .init(
                mode: .local(host: "example.local"),
                mac: "AA:BB:CC:DD:EE:FF"
            ),
            dependencies: dependencies
        )
        weakConnection = connection
        await #expect(throws: TydomConnection.ConnectionError.missingCredentials) {
            try await connection.connect()
        }
    }

    await Task.yield()
    #expect(weakConnection == nil)
    #expect(recorder.value("makeSession") == 1)
    #expect(recorder.value("invalidateSession") == 1)
}

private enum TestError: Error, Equatable {
    case fetchFailed
}

private final class CallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func increment(_ key: String) {
        lock.lock()
        counts[key, default: 0] += 1
        lock.unlock()
    }

    func value(_ key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[key, default: 0]
    }
}
