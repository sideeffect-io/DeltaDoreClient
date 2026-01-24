import Foundation

final class SQLiteEncoder: Encoder {
    var storage: [String: SQLiteValue] = [:]
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]

    private let options: SQLiteCodingOptions

    init(options: SQLiteCodingOptions = .default) {
        self.options = options
    }

    func container<Key>(keyedBy: Key.Type) -> KeyedEncodingContainer<Key> {
        let container = SQLiteKeyedEncodingContainer<Key>(encoder: self)
        return KeyedEncodingContainer(container)
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        SQLiteUnsupportedUnkeyedEncodingContainer(codingPath: codingPath)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        SQLiteUnsupportedSingleValueEncodingContainer(codingPath: codingPath)
    }

    fileprivate func box<T: Encodable>(_ value: T) throws -> SQLiteValue {
        switch value {
        case let value as SQLiteValue:
            return value
        case let value as Bool:
            return .integer(value ? 1 : 0)
        case let value as Int:
            return .integer(Int64(value))
        case let value as Int8:
            return .integer(Int64(value))
        case let value as Int16:
            return .integer(Int64(value))
        case let value as Int32:
            return .integer(Int64(value))
        case let value as Int64:
            return .integer(value)
        case let value as UInt:
            return .integer(Int64(value))
        case let value as UInt8:
            return .integer(Int64(value))
        case let value as UInt16:
            return .integer(Int64(value))
        case let value as UInt32:
            return .integer(Int64(value))
        case let value as UInt64:
            return .integer(Int64(value))
        case let value as Float:
            return .real(Double(value))
        case let value as Double:
            return .real(value)
        case let value as String:
            return .text(value)
        case let value as Data:
            return .blob(value)
        case let value as Date:
            return .real(value.timeIntervalSince1970)
        case let value as URL:
            return .text(value.absoluteString)
        default:
            let encoder = options.jsonEncoder()
            let data = try encoder.encode(value)
            if let string = String(data: data, encoding: .utf8) {
                return .text(string)
            }
            return .blob(data)
        }
    }
}

private struct SQLiteKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    var codingPath: [CodingKey] { encoder.codingPath }
    private let encoder: SQLiteEncoder

    init(encoder: SQLiteEncoder) {
        self.encoder = encoder
    }

    mutating func encodeNil(forKey key: Key) throws {
        encoder.storage[key.stringValue] = .null
    }

    mutating func encode(_ value: Bool, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .integer(value ? 1 : 0)
    }

    mutating func encode(_ value: String, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .text(value)
    }

    mutating func encode(_ value: Double, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .real(value)
    }

    mutating func encode(_ value: Float, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .real(Double(value))
    }

    mutating func encode(_ value: Int, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .integer(Int64(value))
    }

    mutating func encode(_ value: Int8, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .integer(Int64(value))
    }

    mutating func encode(_ value: Int16, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .integer(Int64(value))
    }

    mutating func encode(_ value: Int32, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .integer(Int64(value))
    }

    mutating func encode(_ value: Int64, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .integer(value)
    }

    mutating func encode(_ value: UInt, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .integer(Int64(value))
    }

    mutating func encode(_ value: UInt8, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .integer(Int64(value))
    }

    mutating func encode(_ value: UInt16, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .integer(Int64(value))
    }

    mutating func encode(_ value: UInt32, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .integer(Int64(value))
    }

    mutating func encode(_ value: UInt64, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .integer(Int64(value))
    }

    mutating func encode(_ value: Data, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .blob(value)
    }

    mutating func encode(_ value: Date, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .real(value.timeIntervalSince1970)
    }

    mutating func encode(_ value: URL, forKey key: Key) throws {
        encoder.storage[key.stringValue] = .text(value.absoluteString)
    }

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        encoder.storage[key.stringValue] = try encoder.box(value)
    }

    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        let container = SQLiteUnsupportedKeyedEncodingContainer<NestedKey>(codingPath: codingPath + [key])
        return KeyedEncodingContainer(container)
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        SQLiteUnsupportedUnkeyedEncodingContainer(codingPath: codingPath + [key])
    }

    mutating func superEncoder() -> Encoder {
        SQLiteUnsupportedEncoder(codingPath: codingPath)
    }

    mutating func superEncoder(forKey key: Key) -> Encoder {
        SQLiteUnsupportedEncoder(codingPath: codingPath + [key])
    }
}

private struct SQLiteUnsupportedEncoder: Encoder {
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] = [:]

    func container<Key>(keyedBy: Key.Type) -> KeyedEncodingContainer<Key> {
        let container = SQLiteUnsupportedKeyedEncodingContainer<Key>(codingPath: codingPath)
        return KeyedEncodingContainer(container)
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        SQLiteUnsupportedUnkeyedEncodingContainer(codingPath: codingPath)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        SQLiteUnsupportedSingleValueEncodingContainer(codingPath: codingPath)
    }
}

private struct SQLiteUnsupportedKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let codingPath: [CodingKey]

    mutating func encodeNil(forKey key: Key) throws { throw SQLiteError.unsupportedEncoding("Nested keyed encoding is not supported") }
    mutating func encode(_ value: Bool, forKey key: Key) throws { throw SQLiteError.unsupportedEncoding("Nested keyed encoding is not supported") }
    mutating func encode(_ value: String, forKey key: Key) throws { throw SQLiteError.unsupportedEncoding("Nested keyed encoding is not supported") }
    mutating func encode(_ value: Double, forKey key: Key) throws { throw SQLiteError.unsupportedEncoding("Nested keyed encoding is not supported") }
    mutating func encode(_ value: Float, forKey key: Key) throws { throw SQLiteError.unsupportedEncoding("Nested keyed encoding is not supported") }
    mutating func encode(_ value: Int, forKey key: Key) throws { throw SQLiteError.unsupportedEncoding("Nested keyed encoding is not supported") }
    mutating func encode(_ value: Int8, forKey key: Key) throws { throw SQLiteError.unsupportedEncoding("Nested keyed encoding is not supported") }
    mutating func encode(_ value: Int16, forKey key: Key) throws { throw SQLiteError.unsupportedEncoding("Nested keyed encoding is not supported") }
    mutating func encode(_ value: Int32, forKey key: Key) throws { throw SQLiteError.unsupportedEncoding("Nested keyed encoding is not supported") }
    mutating func encode(_ value: Int64, forKey key: Key) throws { throw SQLiteError.unsupportedEncoding("Nested keyed encoding is not supported") }
    mutating func encode(_ value: UInt, forKey key: Key) throws { throw SQLiteError.unsupportedEncoding("Nested keyed encoding is not supported") }
    mutating func encode(_ value: UInt8, forKey key: Key) throws { throw SQLiteError.unsupportedEncoding("Nested keyed encoding is not supported") }
    mutating func encode(_ value: UInt16, forKey key: Key) throws { throw SQLiteError.unsupportedEncoding("Nested keyed encoding is not supported") }
    mutating func encode(_ value: UInt32, forKey key: Key) throws { throw SQLiteError.unsupportedEncoding("Nested keyed encoding is not supported") }
    mutating func encode(_ value: UInt64, forKey key: Key) throws { throw SQLiteError.unsupportedEncoding("Nested keyed encoding is not supported") }
    mutating func encode(_ value: Data, forKey key: Key) throws { throw SQLiteError.unsupportedEncoding("Nested keyed encoding is not supported") }
    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws { throw SQLiteError.unsupportedEncoding("Nested keyed encoding is not supported") }

    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        let container = SQLiteUnsupportedKeyedEncodingContainer<NestedKey>(codingPath: codingPath + [key])
        return KeyedEncodingContainer(container)
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        SQLiteUnsupportedUnkeyedEncodingContainer(codingPath: codingPath + [key])
    }

    mutating func superEncoder() -> Encoder {
        SQLiteUnsupportedEncoder(codingPath: codingPath)
    }

    mutating func superEncoder(forKey key: Key) -> Encoder {
        SQLiteUnsupportedEncoder(codingPath: codingPath + [key])
    }
}

private struct SQLiteUnsupportedUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    let codingPath: [CodingKey]
    var count: Int { 0 }

    mutating func encodeNil() throws { throw SQLiteError.unsupportedEncoding("Unkeyed encoding is not supported") }
    mutating func encode(_ value: Bool) throws { throw SQLiteError.unsupportedEncoding("Unkeyed encoding is not supported") }
    mutating func encode(_ value: String) throws { throw SQLiteError.unsupportedEncoding("Unkeyed encoding is not supported") }
    mutating func encode(_ value: Double) throws { throw SQLiteError.unsupportedEncoding("Unkeyed encoding is not supported") }
    mutating func encode(_ value: Float) throws { throw SQLiteError.unsupportedEncoding("Unkeyed encoding is not supported") }
    mutating func encode(_ value: Int) throws { throw SQLiteError.unsupportedEncoding("Unkeyed encoding is not supported") }
    mutating func encode(_ value: Int8) throws { throw SQLiteError.unsupportedEncoding("Unkeyed encoding is not supported") }
    mutating func encode(_ value: Int16) throws { throw SQLiteError.unsupportedEncoding("Unkeyed encoding is not supported") }
    mutating func encode(_ value: Int32) throws { throw SQLiteError.unsupportedEncoding("Unkeyed encoding is not supported") }
    mutating func encode(_ value: Int64) throws { throw SQLiteError.unsupportedEncoding("Unkeyed encoding is not supported") }
    mutating func encode(_ value: UInt) throws { throw SQLiteError.unsupportedEncoding("Unkeyed encoding is not supported") }
    mutating func encode(_ value: UInt8) throws { throw SQLiteError.unsupportedEncoding("Unkeyed encoding is not supported") }
    mutating func encode(_ value: UInt16) throws { throw SQLiteError.unsupportedEncoding("Unkeyed encoding is not supported") }
    mutating func encode(_ value: UInt32) throws { throw SQLiteError.unsupportedEncoding("Unkeyed encoding is not supported") }
    mutating func encode(_ value: UInt64) throws { throw SQLiteError.unsupportedEncoding("Unkeyed encoding is not supported") }
    mutating func encode(_ value: Data) throws { throw SQLiteError.unsupportedEncoding("Unkeyed encoding is not supported") }
    mutating func encode<T: Encodable>(_ value: T) throws { throw SQLiteError.unsupportedEncoding("Unkeyed encoding is not supported") }

    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
        let container = SQLiteUnsupportedKeyedEncodingContainer<NestedKey>(codingPath: codingPath)
        return KeyedEncodingContainer(container)
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        SQLiteUnsupportedUnkeyedEncodingContainer(codingPath: codingPath)
    }

    mutating func superEncoder() -> Encoder {
        SQLiteUnsupportedEncoder(codingPath: codingPath)
    }
}

private struct SQLiteUnsupportedSingleValueEncodingContainer: SingleValueEncodingContainer {
    let codingPath: [CodingKey]

    mutating func encodeNil() throws { throw SQLiteError.unsupportedEncoding("Single value encoding is not supported") }
    mutating func encode(_ value: Bool) throws { throw SQLiteError.unsupportedEncoding("Single value encoding is not supported") }
    mutating func encode(_ value: String) throws { throw SQLiteError.unsupportedEncoding("Single value encoding is not supported") }
    mutating func encode(_ value: Double) throws { throw SQLiteError.unsupportedEncoding("Single value encoding is not supported") }
    mutating func encode(_ value: Float) throws { throw SQLiteError.unsupportedEncoding("Single value encoding is not supported") }
    mutating func encode(_ value: Int) throws { throw SQLiteError.unsupportedEncoding("Single value encoding is not supported") }
    mutating func encode(_ value: Int8) throws { throw SQLiteError.unsupportedEncoding("Single value encoding is not supported") }
    mutating func encode(_ value: Int16) throws { throw SQLiteError.unsupportedEncoding("Single value encoding is not supported") }
    mutating func encode(_ value: Int32) throws { throw SQLiteError.unsupportedEncoding("Single value encoding is not supported") }
    mutating func encode(_ value: Int64) throws { throw SQLiteError.unsupportedEncoding("Single value encoding is not supported") }
    mutating func encode(_ value: UInt) throws { throw SQLiteError.unsupportedEncoding("Single value encoding is not supported") }
    mutating func encode(_ value: UInt8) throws { throw SQLiteError.unsupportedEncoding("Single value encoding is not supported") }
    mutating func encode(_ value: UInt16) throws { throw SQLiteError.unsupportedEncoding("Single value encoding is not supported") }
    mutating func encode(_ value: UInt32) throws { throw SQLiteError.unsupportedEncoding("Single value encoding is not supported") }
    mutating func encode(_ value: UInt64) throws { throw SQLiteError.unsupportedEncoding("Single value encoding is not supported") }
    mutating func encode(_ value: Data) throws { throw SQLiteError.unsupportedEncoding("Single value encoding is not supported") }
    mutating func encode<T: Encodable>(_ value: T) throws { throw SQLiteError.unsupportedEncoding("Single value encoding is not supported") }
}
