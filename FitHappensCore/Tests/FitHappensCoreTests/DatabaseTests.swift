@testable import FitHappensCore
import SQLiteData
import Testing

struct DatabaseTests {
  @Test func firstMigrationCreatesTheCoreTables() throws {
    let database = try DatabaseQueue()
    try FitHappensDatabaseMigrations.makeMigrator().migrate(database)
    let tableNames = try database.read { connection in
      try String.fetchAll(
        connection,
        sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
      )
    }
    #expect(Set(tableNames).isSuperset(of: [
      "exercises", "workouts", "workoutItems", "programRevisions", "completions", "completionItems"
    ]))
  }
}
