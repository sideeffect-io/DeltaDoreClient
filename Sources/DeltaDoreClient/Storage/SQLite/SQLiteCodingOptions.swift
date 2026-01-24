import Foundation

struct SQLiteCodingOptions: Sendable {
    let jsonEncoder: @Sendable () -> JSONEncoder
    let jsonDecoder: @Sendable () -> JSONDecoder

    init(
        jsonEncoder: @escaping @Sendable () -> JSONEncoder = { JSONEncoder() },
        jsonDecoder: @escaping @Sendable () -> JSONDecoder = { JSONDecoder() }
    ) {
        self.jsonEncoder = jsonEncoder
        self.jsonDecoder = jsonDecoder
    }

    static let `default` = SQLiteCodingOptions()
}
