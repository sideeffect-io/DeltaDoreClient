import Foundation
import Testing

@testable import DeltaDoreClient

@Suite(.serialized) struct TydomCloudPasswordProviderTests {
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    @Test func fetchGatewayPasswordSuccess() async throws {
        let session = makeMockSession()
        let mac = "AA:BB:CC:DD:EE:FF"
        let tokenEndpoint = "https://auth.example.com/token"

        MockURLProtocol.setHandler { request in
            guard let url = request.url?.absoluteString else {
                throw TestError.invalidRequest
            }

            switch url {
            case TydomCloudPasswordProvider.Constants.authURL:
                return response(url: url, json: ["token_endpoint": tokenEndpoint])
            case tokenEndpoint:
                return response(url: url, json: ["access_token": "token-123"])
            case TydomCloudPasswordProvider.Constants.sitesAPI + mac:
                return response(url: url, json: [
                    "sites": [
                        ["gateway": ["mac": mac, "password": "gw-pass"]]
                    ]
                ])
            default:
                throw TestError.unhandledURL(url)
            }
        }
        defer { MockURLProtocol.clearHandler() }

        let password = try await TydomCloudPasswordProvider.fetchGatewayPassword(
            email: "user@example.com",
            password: "secret",
            mac: mac,
            session: session
        )

        #expect(password == "gw-pass")
    }

    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    @Test func fetchGatewayPasswordThrowsWhenGatewayNotFound() async {
        let session = makeMockSession()
        let mac = "AA:BB:CC:DD:EE:FF"
        let tokenEndpoint = "https://auth.example.com/token"

        MockURLProtocol.setHandler { request in
            guard let url = request.url?.absoluteString else {
                throw TestError.invalidRequest
            }

            switch url {
            case TydomCloudPasswordProvider.Constants.authURL:
                return response(url: url, json: ["token_endpoint": tokenEndpoint])
            case tokenEndpoint:
                return response(url: url, json: ["access_token": "token-123"])
            case TydomCloudPasswordProvider.Constants.sitesAPI + mac:
                return response(url: url, json: ["sites": []])
            default:
                throw TestError.unhandledURL(url)
            }
        }
        defer { MockURLProtocol.clearHandler() }

        let error = await #expect(throws: TydomCloudPasswordProvider.ProviderError.self) {
            _ = try await TydomCloudPasswordProvider.fetchGatewayPassword(
                email: "user@example.com",
                password: "secret",
                mac: mac,
                session: session
            )
        }

        if let error {
            let isGatewayNotFound: Bool
            switch error {
            case .gatewayNotFound:
                isGatewayNotFound = true
            default:
                isGatewayNotFound = false
            }
            #expect(isGatewayNotFound)
        } else {
            #expect(Bool(false))
        }
    }
}

private func makeMockSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func response(url: String, json: [String: Any]) -> (HTTPURLResponse, Data) {
    let data = try! JSONSerialization.data(withJSONObject: json, options: [])
    let response = HTTPURLResponse(
        url: URL(string: url)!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
    return (response, data)
}

private enum TestError: Error {
    case invalidRequest
    case unhandledURL(String)
}

private final class MockURLProtocol: URLProtocol {
    static func setHandler(_ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        HandlerBox.shared.set(handler)
    }

    static func clearHandler() {
        HandlerBox.shared.clear()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = HandlerBox.shared.get() else {
            client?.urlProtocol(self, didFailWithError: TestError.invalidRequest)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class HandlerBox: @unchecked Sendable {
    static let shared = HandlerBox()
    private let lock = NSLock()
    private var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    func set(_ newHandler: @Sendable @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        handler = newHandler
        lock.unlock()
    }

    func clear() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    func get() -> (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        lock.lock()
        defer { lock.unlock() }
        return handler
    }
}
