import Foundation

enum SQLiteError: Error, Sendable, Equatable {
    case openFailed(message: String)
    case prepareFailed(message: String)
    case stepFailed(message: String)
    case bindFailed(message: String)
    case executionFailed(message: String)
    case columnNotFound(String)
    case typeMismatch(column: String, expected: String, actual: SQLiteValue)
    case missingPrimaryKey(String)
    case unsupportedEncoding(String)
    case unsupportedDecoding(String)
    case decodingFailed(message: String)
}
