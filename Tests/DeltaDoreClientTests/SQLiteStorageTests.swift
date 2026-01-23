import Foundation
import Testing
@testable import DeltaDoreClient

private struct User: Codable, Sendable, Equatable {
    let id: Int64
    let name: String
    let role: Role
    let metadata: Metadata?
}

private enum Role: String, Codable, Sendable {
    case admin
    case user
}

private struct Metadata: Codable, Sendable, Equatable {
    let lastLogin: Date
    let tags: [String]
}

@Test func sqliteCRUD() async throws {
    // Given
    let database = try await SQLiteDatabase(path: ":memory:")
    try await database.execute(
        """
        CREATE TABLE users (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            role TEXT NOT NULL,
            metadata TEXT
        )
        """
    )

    let schema = TableSchema<User>.codable(table: "users", primaryKey: "id")
    let dao = DAO.make(database: database, schema: schema)

    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let user = User(
        id: 1,
        name: "Ada",
        role: .admin,
        metadata: Metadata(lastLogin: date, tags: ["swift", "sqlite"])
    )

    // When
    _ = try await dao.create(user)
    let fetched = try await dao.read(.integer(1))
    #expect(fetched == user)

    let updated = User(
        id: 1,
        name: "Ada Lovelace",
        role: .admin,
        metadata: user.metadata
    )
    _ = try await dao.update(updated)
    let fetchedUpdated = try await dao.read(.integer(1))
    #expect(fetchedUpdated == updated)

    let other = User(id: 2, name: "Grace", role: .user, metadata: nil)
    _ = try await dao.create(other)

    let all = try await dao.list()
    #expect(all.count == 2)

    try await dao.delete(.integer(1))
    let deleted = try await dao.read(.integer(1))
    #expect(deleted == nil)
}

@Test func sqliteJoinRows() async throws {
    // Given
    let database = try await SQLiteDatabase(path: ":memory:")
    try await database.execute("PRAGMA foreign_keys = ON")
    try await database.execute(
        """
        CREATE TABLE users (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL
        )
        """
    )
    try await database.execute(
        """
        CREATE TABLE posts (
            id INTEGER PRIMARY KEY,
            authorId INTEGER NOT NULL,
            title TEXT NOT NULL,
            FOREIGN KEY(authorId) REFERENCES users(id) ON DELETE CASCADE
        )
        """
    )

    try await database.execute("INSERT INTO users (id, name) VALUES (?, ?)", [.integer(1), .text("Ada")])
    try await database.execute("INSERT INTO posts (id, authorId, title) VALUES (?, ?, ?)", [.integer(10), .integer(1), .text("Notes")])

    let userSchema = TableSchema<User>.codable(table: "users", primaryKey: "id")
    let userDao = DAO.make(database: database, schema: userSchema)

    // When
    let rows = try await userDao.queryRows(
        """
        SELECT users.name AS userName, posts.title AS postTitle
        FROM posts
        JOIN users ON users.id = posts.authorId
        WHERE users.id = ?
        """,
        [.integer(1)]
    )

    let result = rows.map { row in
        (row.columns["userName"], row.columns["postTitle"])
    }

    // Then
    #expect(result.count == 1)
    #expect(result[0].0 == .text("Ada"))
    #expect(result[0].1 == .text("Notes"))
}
