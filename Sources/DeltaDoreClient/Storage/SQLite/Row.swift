import Foundation

public struct Row: Sendable, Equatable {
    public let columns: [String: SQLiteValue]

    public init(columns: [String: SQLiteValue]) {
        self.columns = columns
    }

    public func value(_ name: String) -> SQLiteValue? {
        columns[name]
    }
}
