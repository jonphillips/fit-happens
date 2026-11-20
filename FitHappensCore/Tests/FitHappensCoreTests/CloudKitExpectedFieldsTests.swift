@testable import FitHappensCore
import Foundation
import SQLiteData
import Testing

struct CloudKitExpectedFieldsTests {
  @Test func expectedFieldsExactlyCoverTheSixSyncedTablesAfterEveryMigration() throws {
    let database = try DatabaseQueue()
    defer { try? database.close() }
    try FitHappensDatabaseMigrations.makeMigrator().migrate(database)
    let syncedTables = [
      "exercises", "workouts", "workoutItems", "programRevisions", "completions", "completionItems"
    ]
    let fieldsFromMigrations = try database.read { connection in
      try syncedTables.reduce(into: Set<String>()) { fields, table in
        let columns = try String.fetchAll(
          connection,
          sql: "SELECT name || '|' || type FROM pragma_table_info(?)",
          arguments: [table]
        )
        fields.insert("\(table) sqlitedata_icloud_userModificationTime")
        for column in columns {
          let components = column.split(separator: "|", maxSplits: 1)
          guard components.count == 2 else { continue }
          let name = String(components[0])
          let type = String(components[1])
          fields.insert("\(table) \(name)")
          fields.insert("\(table) sqlitedata_icloud_userModificationTime_\(name)")
          if type.uppercased() == "BLOB" {
            fields.insert("\(table) \(name)_hash")
          }
        }
      }
    }
    let repositoryRoot = repositoryRoot()
    let expectedFields = Set(
      try String(contentsOf: repositoryRoot.appending(path: "cloudkit-expected-fields.txt"), encoding: .utf8)
        .split(whereSeparator: \.isNewline)
        .map(String.init)
    )

    #expect(expectedFields == fieldsFromMigrations)
  }
}

private func repositoryRoot() -> URL {
  var directory = URL(filePath: #filePath).deletingLastPathComponent()
  while directory.path != "/" {
    if FileManager.default.fileExists(atPath: directory.appending(path: "cloudkit-expected-fields.txt").path) {
      return directory
    }
    directory.deleteLastPathComponent()
  }
  return URL(filePath: #filePath)
}
