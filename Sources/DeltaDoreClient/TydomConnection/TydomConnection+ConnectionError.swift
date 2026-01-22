import Foundation

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
public extension TydomConnection {
    enum ConnectionError: Error, Sendable, Equatable {
        case missingCredentials
        case missingPassword
        case missingChallenge
        case invalidChallenge
        case unsupportedAlgorithm(String)
        case unsupportedQop(String)
        case invalidResponse
        case notConnected
        case receiveFailed
    }
}
