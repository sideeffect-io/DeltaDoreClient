import Foundation

struct Row: Sendable, Equatable {
    let columns: [String: SQLiteValue]

    init(columns: [String: SQLiteValue]) {
        self.columns = columns
    }

    func value(_ name: String) -> SQLiteValue? {
        columns[name]
    }
}
