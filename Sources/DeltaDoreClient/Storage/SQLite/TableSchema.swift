import Foundation

public struct TableSchema<Entity: Codable & Sendable>: Sendable {
    public let table: String
    public let primaryKey: String
    public let encode: @Sendable (Entity) throws -> [String: SQLiteValue]
    public let decode: @Sendable (Row) throws -> Entity

    public init(
        table: String,
        primaryKey: String,
        encode: @escaping @Sendable (Entity) throws -> [String: SQLiteValue],
        decode: @escaping @Sendable (Row) throws -> Entity
    ) {
        self.table = table
        self.primaryKey = primaryKey
        self.encode = encode
        self.decode = decode
    }
}

public extension TableSchema {
    static func codable(
        table: String,
        primaryKey: String,
        options: SQLiteCodingOptions = .default
    ) -> TableSchema<Entity> {
        TableSchema(
            table: table,
            primaryKey: primaryKey,
            encode: { entity in
                let encoder = SQLiteEncoder(options: options)
                try entity.encode(to: encoder)
                return encoder.storage
            },
            decode: { row in
                try Entity(from: SQLiteDecoder(row: row, options: options))
            }
        )
    }
}
