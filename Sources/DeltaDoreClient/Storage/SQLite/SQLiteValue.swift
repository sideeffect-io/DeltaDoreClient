import Foundation

enum SQLiteValue: Sendable, Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

extension SQLiteValue {
    var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}
