import Foundation

extension TydomConnection {
    public enum ConnectionError: Error, Sendable, Equatable {
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
