import Foundation
import SQLite3

actor SQLiteDatabase {
    private let handle: SQLiteHandle

    init(path: String) async throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
            let message = SQLiteDatabase.errorMessage(from: db)
            sqlite3_close(db)
            throw SQLiteError.openFailed(message: message)
        }
        let sqliteHandle = SQLiteHandle(pointer: db)
        self.handle = sqliteHandle
        try await execute("PRAGMA foreign_keys = ON")
    }

    func execute(_ sql: String, _ bindings: [SQLiteValue] = []) async throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement)

        let result = sqlite3_step(statement)
        if result != SQLITE_DONE {
            throw SQLiteError.executionFailed(message: errorMessage())
        }
    }

    func query(_ sql: String, _ bindings: [SQLiteValue] = []) async throws -> [Row] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement)

        var rows: [Row] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                rows.append(readRow(from: statement))
                continue
            }
            if result == SQLITE_DONE {
                break
            }
            throw SQLiteError.executionFailed(message: errorMessage())
        }
        return rows
    }

    func withTransaction<T: Sendable>(
        _ work: @Sendable (SQLiteDatabase) async throws -> T
    ) async throws -> T {
        try await execute("BEGIN")
        do {
            let result = try await work(self)
            try await execute("COMMIT")
            return result
        } catch {
            try await execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(handle.pointer, sql, -1, &statement, nil) != SQLITE_OK {
            throw SQLiteError.prepareFailed(message: errorMessage())
        }
        guard let statement else {
            throw SQLiteError.prepareFailed(message: "Failed to prepare statement")
        }
        return statement
    }

    private func bind(_ bindings: [SQLiteValue], to statement: OpaquePointer) throws {
        for (index, value) in bindings.enumerated() {
            let position = Int32(index + 1)
            let result: Int32
            switch value {
            case .null:
                result = sqlite3_bind_null(statement, position)
            case .integer(let int):
                result = sqlite3_bind_int64(statement, position, int)
            case .real(let double):
                result = sqlite3_bind_double(statement, position, double)
            case .text(let text):
                let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                result = sqlite3_bind_text(statement, position, text, -1, transient)
            case .blob(let data):
                result = data.withUnsafeBytes { bytes in
                    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                    return sqlite3_bind_blob(statement, position, bytes.baseAddress, Int32(data.count), transient)
                }
            }

            if result != SQLITE_OK {
                throw SQLiteError.bindFailed(message: SQLiteDatabase.errorMessage(from: handle.pointer))
            }
        }
    }

    private func readRow(from statement: OpaquePointer) -> Row {
        let count = sqlite3_column_count(statement)
        var columns: [String: SQLiteValue] = [:]
        columns.reserveCapacity(Int(count))

        for index in 0..<count {
            guard let namePointer = sqlite3_column_name(statement, index) else { continue }
            let name = String(cString: namePointer)
            columns[name] = readColumn(from: statement, index: index)
        }

        return Row(columns: columns)
    }

    private func readColumn(from statement: OpaquePointer, index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let pointer = sqlite3_column_text(statement, index) else {
                return .text("")
            }
            return .text(String(cString: pointer))
        case SQLITE_BLOB:
            guard let bytes = sqlite3_column_blob(statement, index) else {
                return .blob(Data())
            }
            let count = Int(sqlite3_column_bytes(statement, index))
            return .blob(Data(bytes: bytes, count: count))
        default:
            return .null
        }
    }

    private func errorMessage() -> String {
        return SQLiteDatabase.errorMessage(from: handle.pointer)
    }

    private static func errorMessage(from handle: OpaquePointer?) -> String {
        guard let handle, let message = sqlite3_errmsg(handle) else {
            return "Unknown SQLite error"
        }
        return String(cString: message)
    }
}

private final class SQLiteHandle {
    let pointer: OpaquePointer?

    init(pointer: OpaquePointer?) {
        self.pointer = pointer
    }

    deinit {
        if let pointer {
            sqlite3_close(pointer)
        }
    }
}
