import Foundation

struct TableSchema<Entity: Codable & Sendable>: Sendable {
    let table: String
    let primaryKey: String
    let encode: @Sendable (Entity) throws -> [String: SQLiteValue]
    let decode: @Sendable (Row) throws -> Entity

    init(
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

extension TableSchema {
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
