import Foundation

public struct SQLiteCodingOptions: Sendable {
    public let jsonEncoder: @Sendable () -> JSONEncoder
    public let jsonDecoder: @Sendable () -> JSONDecoder

    public init(
        jsonEncoder: @escaping @Sendable () -> JSONEncoder = { JSONEncoder() },
        jsonDecoder: @escaping @Sendable () -> JSONDecoder = { JSONDecoder() }
    ) {
        self.jsonEncoder = jsonEncoder
        self.jsonDecoder = jsonDecoder
    }

    public static let `default` = SQLiteCodingOptions()
}
