import Foundation

struct SQLiteDecoder: Decoder {
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]

    private let row: Row
    private let options: SQLiteCodingOptions

    init(row: Row, options: SQLiteCodingOptions = .default) {
        self.row = row
        self.options = options
    }

    func container<Key>(keyedBy type: Key.Type) -> KeyedDecodingContainer<Key> {
        let container = SQLiteKeyedDecodingContainer<Key>(decoder: self, row: row)
        return KeyedDecodingContainer(container)
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw SQLiteError.unsupportedDecoding("Unkeyed decoding is not supported")
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        throw SQLiteError.unsupportedDecoding("Single value decoding is not supported")
    }

    fileprivate func unbox<T: Decodable>(_ value: SQLiteValue, as type: T.Type, column: String) throws -> T {
        if type == Bool.self {
            return try decodeBool(value, column: column) as! T
        }
        if type == String.self {
            return try decodeString(value, column: column) as! T
        }
        if type == Double.self {
            return try decodeDouble(value, column: column) as! T
        }
        if type == Float.self {
            return try Float(decodeDouble(value, column: column)) as! T
        }
        if type == Int.self {
            return try Int(decodeInt64(value, column: column)) as! T
        }
        if type == Int8.self {
            return try Int8(decodeInt64(value, column: column)) as! T
        }
        if type == Int16.self {
            return try Int16(decodeInt64(value, column: column)) as! T
        }
        if type == Int32.self {
            return try Int32(decodeInt64(value, column: column)) as! T
        }
        if type == Int64.self {
            return try decodeInt64(value, column: column) as! T
        }
        if type == UInt.self {
            return try UInt(decodeInt64(value, column: column)) as! T
        }
        if type == UInt8.self {
            return try UInt8(decodeInt64(value, column: column)) as! T
        }
        if type == UInt16.self {
            return try UInt16(decodeInt64(value, column: column)) as! T
        }
        if type == UInt32.self {
            return try UInt32(decodeInt64(value, column: column)) as! T
        }
        if type == UInt64.self {
            return try UInt64(decodeInt64(value, column: column)) as! T
        }
        if type == Data.self {
            return try decodeData(value, column: column) as! T
        }
        if type == Date.self {
            return try decodeDate(value, column: column) as! T
        }
        if type == URL.self {
            return try decodeURL(value, column: column) as! T
        }

        let data = try decodeJSONData(value, column: column)
        let decoder = options.jsonDecoder()
        return try decoder.decode(T.self, from: data)
    }

    private func decodeInt64(_ value: SQLiteValue, column: String) throws -> Int64 {
        switch value {
        case .integer(let int):
            return int
        case .real(let double):
            return Int64(double)
        default:
            throw SQLiteError.typeMismatch(column: column, expected: "Int64", actual: value)
        }
    }

    private func decodeDouble(_ value: SQLiteValue, column: String) throws -> Double {
        switch value {
        case .real(let double):
            return double
        case .integer(let int):
            return Double(int)
        default:
            throw SQLiteError.typeMismatch(column: column, expected: "Double", actual: value)
        }
    }

    private func decodeString(_ value: SQLiteValue, column: String) throws -> String {
        switch value {
        case .text(let string):
            return string
        default:
            throw SQLiteError.typeMismatch(column: column, expected: "String", actual: value)
        }
    }

    private func decodeBool(_ value: SQLiteValue, column: String) throws -> Bool {
        switch value {
        case .integer(let int):
            return int != 0
        case .real(let double):
            return double != 0
        case .text(let string):
            return (string as NSString).boolValue
        default:
            throw SQLiteError.typeMismatch(column: column, expected: "Bool", actual: value)
        }
    }

    private func decodeData(_ value: SQLiteValue, column: String) throws -> Data {
        switch value {
        case .blob(let data):
            return data
        case .text(let string):
            guard let data = string.data(using: .utf8) else {
                throw SQLiteError.typeMismatch(column: column, expected: "Data", actual: value)
            }
            return data
        default:
            throw SQLiteError.typeMismatch(column: column, expected: "Data", actual: value)
        }
    }

    private func decodeDate(_ value: SQLiteValue, column: String) throws -> Date {
        let seconds = try decodeDouble(value, column: column)
        return Date(timeIntervalSince1970: seconds)
    }

    private func decodeURL(_ value: SQLiteValue, column: String) throws -> URL {
        let string = try decodeString(value, column: column)
        guard let url = URL(string: string) else {
            throw SQLiteError.decodingFailed(message: "Invalid URL string")
        }
        return url
    }

    private func decodeJSONData(_ value: SQLiteValue, column: String) throws -> Data {
        switch value {
        case .text(let string):
            guard let data = string.data(using: .utf8) else {
                throw SQLiteError.decodingFailed(message: "Invalid JSON text")
            }
            return data
        case .blob(let data):
            return data
        default:
            throw SQLiteError.typeMismatch(column: column, expected: "JSON", actual: value)
        }
    }
}

private struct SQLiteKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let codingPath: [CodingKey]
    let allKeys: [Key]

    private let decoder: SQLiteDecoder
    private let row: Row

    init(decoder: SQLiteDecoder, row: Row) {
        self.decoder = decoder
        self.row = row
        self.codingPath = decoder.codingPath
        self.allKeys = row.columns.keys.compactMap { Key(stringValue: $0) }
    }

    func contains(_ key: Key) -> Bool {
        row.columns[key.stringValue] != nil
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        guard let value = row.columns[key.stringValue] else {
            return true
        }
        return value.isNull
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        try decoder.unbox(try value(forKey: key), as: Bool.self, column: key.stringValue)
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        try decoder.unbox(try value(forKey: key), as: String.self, column: key.stringValue)
    }

    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        try decoder.unbox(try value(forKey: key), as: Double.self, column: key.stringValue)
    }

    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        try decoder.unbox(try value(forKey: key), as: Float.self, column: key.stringValue)
    }

    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        try decoder.unbox(try value(forKey: key), as: Int.self, column: key.stringValue)
    }

    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        try decoder.unbox(try value(forKey: key), as: Int8.self, column: key.stringValue)
    }

    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        try decoder.unbox(try value(forKey: key), as: Int16.self, column: key.stringValue)
    }

    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        try decoder.unbox(try value(forKey: key), as: Int32.self, column: key.stringValue)
    }

    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        try decoder.unbox(try value(forKey: key), as: Int64.self, column: key.stringValue)
    }

    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        try decoder.unbox(try value(forKey: key), as: UInt.self, column: key.stringValue)
    }

    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        try decoder.unbox(try value(forKey: key), as: UInt8.self, column: key.stringValue)
    }

    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        try decoder.unbox(try value(forKey: key), as: UInt16.self, column: key.stringValue)
    }

    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        try decoder.unbox(try value(forKey: key), as: UInt32.self, column: key.stringValue)
    }

    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        try decoder.unbox(try value(forKey: key), as: UInt64.self, column: key.stringValue)
    }

    func decode(_ type: Data.Type, forKey key: Key) throws -> Data {
        try decoder.unbox(try value(forKey: key), as: Data.self, column: key.stringValue)
    }

    func decode(_ type: Date.Type, forKey key: Key) throws -> Date {
        try decoder.unbox(try value(forKey: key), as: Date.self, column: key.stringValue)
    }

    func decode(_ type: URL.Type, forKey key: Key) throws -> URL {
        try decoder.unbox(try value(forKey: key), as: URL.self, column: key.stringValue)
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        try decoder.unbox(try value(forKey: key), as: T.self, column: key.stringValue)
    }

    func decodeIfPresent(_ type: Bool.Type, forKey key: Key) throws -> Bool? {
        try decodeIfPresentValue(type, forKey: key)
    }

    func decodeIfPresent(_ type: String.Type, forKey key: Key) throws -> String? {
        try decodeIfPresentValue(type, forKey: key)
    }

    func decodeIfPresent(_ type: Double.Type, forKey key: Key) throws -> Double? {
        try decodeIfPresentValue(type, forKey: key)
    }

    func decodeIfPresent(_ type: Float.Type, forKey key: Key) throws -> Float? {
        try decodeIfPresentValue(type, forKey: key)
    }

    func decodeIfPresent(_ type: Int.Type, forKey key: Key) throws -> Int? {
        try decodeIfPresentValue(type, forKey: key)
    }

    func decodeIfPresent(_ type: Int8.Type, forKey key: Key) throws -> Int8? {
        try decodeIfPresentValue(type, forKey: key)
    }

    func decodeIfPresent(_ type: Int16.Type, forKey key: Key) throws -> Int16? {
        try decodeIfPresentValue(type, forKey: key)
    }

    func decodeIfPresent(_ type: Int32.Type, forKey key: Key) throws -> Int32? {
        try decodeIfPresentValue(type, forKey: key)
    }

    func decodeIfPresent(_ type: Int64.Type, forKey key: Key) throws -> Int64? {
        try decodeIfPresentValue(type, forKey: key)
    }

    func decodeIfPresent(_ type: UInt.Type, forKey key: Key) throws -> UInt? {
        try decodeIfPresentValue(type, forKey: key)
    }

    func decodeIfPresent(_ type: UInt8.Type, forKey key: Key) throws -> UInt8? {
        try decodeIfPresentValue(type, forKey: key)
    }

    func decodeIfPresent(_ type: UInt16.Type, forKey key: Key) throws -> UInt16? {
        try decodeIfPresentValue(type, forKey: key)
    }

    func decodeIfPresent(_ type: UInt32.Type, forKey key: Key) throws -> UInt32? {
        try decodeIfPresentValue(type, forKey: key)
    }

    func decodeIfPresent(_ type: UInt64.Type, forKey key: Key) throws -> UInt64? {
        try decodeIfPresentValue(type, forKey: key)
    }

    func decodeIfPresent(_ type: Data.Type, forKey key: Key) throws -> Data? {
        try decodeIfPresentValue(type, forKey: key)
    }

    func decodeIfPresent(_ type: Date.Type, forKey key: Key) throws -> Date? {
        try decodeIfPresentValue(type, forKey: key)
    }

    func decodeIfPresent(_ type: URL.Type, forKey key: Key) throws -> URL? {
        try decodeIfPresentValue(type, forKey: key)
    }

    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        try decodeIfPresentValue(type, forKey: key)
    }

    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        throw SQLiteError.unsupportedDecoding("Nested keyed decoding is not supported")
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        throw SQLiteError.unsupportedDecoding("Nested unkeyed decoding is not supported")
    }

    func superDecoder() throws -> Decoder {
        throw SQLiteError.unsupportedDecoding("Super decoder is not supported")
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        throw SQLiteError.unsupportedDecoding("Super decoder is not supported")
    }

    private func value(forKey key: Key) throws -> SQLiteValue {
        guard let value = row.columns[key.stringValue] else {
            throw SQLiteError.columnNotFound(key.stringValue)
        }
        return value
    }

    private func decodeIfPresentValue<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        guard let value = row.columns[key.stringValue] else {
            return nil
        }
        if value.isNull {
            return nil
        }
        return try decoder.unbox(value, as: T.self, column: key.stringValue)
    }
}
