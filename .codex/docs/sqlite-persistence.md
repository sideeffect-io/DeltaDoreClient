# SQLite persistence

## Summary of changes

- Added a lightweight SQLite persistence layer with a per-connection `SQLiteDatabase` actor.
- Introduced a `Codable`-driven `SQLiteEncoder`/`SQLiteDecoder` so entities only need `Codable` (plus `Sendable`).
- Added a generic `DAO` for CRUD operations with optional raw SQL queries and row access.
- Enabled SQLite foreign keys at connection initialization.
- Added tests for CRUD and join-style queries using `queryRows`.
- Enabled strict concurrency in the Swift package manifest for both main and test targets.

## How it works

### Core types

- `SQLiteDatabase`: actor that owns the SQLite connection and serializes all access.
- `SQLiteValue`: storage representation for bindings and row values.
- `Row`: a simple column-name to `SQLiteValue` map.
- `SQLiteEncoder`/`SQLiteDecoder`: custom `Codable` encoder/decoder that map keys to columns.
- `TableSchema`: describes how to map a `Codable` entity to a table and primary key.
- `DAO`: generic CRUD interface with optional `query` and `queryRows` helpers.

### Encoding/decoding

`SQLiteEncoder` and `SQLiteDecoder` implement keyed containers and map `CodingKey.stringValue` to column names.
Supported scalar mappings are stored as direct `SQLiteValue`s. Nested types are encoded as JSON text by default.

### Concurrency

SQLite is accessed through a single actor instance per connection. This ensures serialization without forcing a
global executor. If more throughput is needed, a connection pool can be added later.

### Foreign keys

`SQLiteDatabase` runs `PRAGMA foreign_keys = ON` during initialization.

## How to use

### 1) Create the schema and DAO

```swift
struct User: Codable, Sendable {
    let id: Int64
    let name: String
    let role: Role
}

enum Role: String, Codable, Sendable { case admin, user }

let db = try await SQLiteDatabase(path: ":memory:")
try await db.execute(
    """
    CREATE TABLE users (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        role TEXT NOT NULL
    )
    """
)

let schema = TableSchema<User>.codable(table: "users", primaryKey: "id")
let users = DAO.make(database: db, schema: schema)
```

### 2) CRUD operations

```swift
let user = User(id: 1, name: "Ada", role: .admin)
_ = try await users.create(user)
let fetched = try await users.read(.integer(1))
let updated = User(id: 1, name: "Ada Lovelace", role: .admin)
_ = try await users.update(updated)
try await users.delete(.integer(1))
```

### 3) Ad-hoc queries

```swift
let admins = try await users.query(
    "SELECT * FROM users WHERE role = ?",
    [.text("admin")]
)
```

### 4) Joins with manual mapping

Use `queryRows` for multi-table results or custom projections:

```swift
let rows = try await users.queryRows(
    """
    SELECT users.name AS userName, posts.title AS postTitle
    FROM posts
    JOIN users ON users.id = posts.authorId
    WHERE users.id = ?
    """,
    [.integer(1)]
)

let values = rows.map { row in
    (row.columns["userName"], row.columns["postTitle"])
}
```

## Extending to a higher-level join API

If you want a more expressive join API, keep it pure and build on top of `queryRows`:

### Option A: Join query helpers

Create a small helper that returns rows and maps them into an aggregate type:

```swift
struct JoinQuery<Output: Sendable> {
    let sql: String
    let bindings: [SQLiteValue]
    let map: @Sendable (Row) throws -> Output
}

func run<Output: Sendable>(
    database: SQLiteDatabase,
    query: JoinQuery<Output>
) async throws -> [Output] {
    let rows = try await database.query(query.sql, query.bindings)
    return try rows.map(query.map)
}
```

### Option B: Repository layer

Create a repository layer that composes DAOs and exposes domain-focused operations:

```swift
struct UserWithPosts: Sendable {
    let user: User
    let posts: [Post]
}

func loadUserWithPosts(
    id: Int64,
    users: DAO<User>,
    posts: DAO<Post>
) async throws -> UserWithPosts? {
    guard let user = try await users.read(.integer(id)) else { return nil }
    let rows = try await posts.query(
        "SELECT * FROM posts WHERE authorId = ?",
        [.integer(id)]
    )
    return UserWithPosts(user: user, posts: rows)
}
```

### Guidance

- Keep entities `Codable` only; store relationship edges as foreign keys.
- Perform joins in repositories or dedicated query helpers.
- If aggregates grow complex, define explicit mapping functions from `Row` to domain types.
- Keep SQL in the persistence layer; keep domain types pure and immutable.

## Files added

- `Sources/DeltaDoreClient/Storage/SQLite/SQLiteDatabase.swift`
- `Sources/DeltaDoreClient/Storage/SQLite/SQLiteEncoder.swift`
- `Sources/DeltaDoreClient/Storage/SQLite/SQLiteDecoder.swift`
- `Sources/DeltaDoreClient/Storage/SQLite/SQLiteCodingOptions.swift`
- `Sources/DeltaDoreClient/Storage/SQLite/SQLiteValue.swift`
- `Sources/DeltaDoreClient/Storage/SQLite/Row.swift`
- `Sources/DeltaDoreClient/Storage/SQLite/SQLiteError.swift`
- `Sources/DeltaDoreClient/Storage/SQLite/TableSchema.swift`
- `Sources/DeltaDoreClient/Storage/SQLite/DAO.swift`

## Tests

- `Tests/DeltaDoreClientTests/SQLiteStorageTests.swift`
