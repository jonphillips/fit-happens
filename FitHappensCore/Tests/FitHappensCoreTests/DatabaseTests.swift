@testable import FitHappensCore
import Foundation
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

  @Test func currentProgramQuerySeparatesRetiredExercises() throws {
    let database = try DatabaseQueue()
    try FitHappensDatabaseMigrations.makeMigrator().migrate(database)
    let active = Exercise(
      id: UUID(), key: "bench", name: "Bench", loadKind: .weight, currentLoadPounds: 135
    )
    let retired = Exercise(
      id: UUID(), key: "old-row", name: "Old row", loadKind: .weight,
      currentLoadPounds: 90, isRetired: true
    )
    let workout = Workout(id: UUID(), key: "A", position: 0)
    try database.write { connection in
      try Exercise.insert { Exercise.Draft(active) }.execute(connection)
      try Exercise.insert { Exercise.Draft(retired) }.execute(connection)
      try Workout.insert { Workout.Draft(workout) }.execute(connection)
      try WorkoutItem.insert {
        WorkoutItem.Draft(WorkoutItem(
          id: UUID(), workoutID: workout.id, exerciseID: active.id,
          position: 0, prescription: "3 × 5–8"
        ))
      }.execute(connection)
      try WorkoutItem.insert {
        WorkoutItem.Draft(WorkoutItem(
          id: UUID(), workoutID: workout.id, exerciseID: retired.id,
          position: 1, prescription: "3 × 8–12"
        ))
      }.execute(connection)
    }
    let current = try database.read { try CurrentProgramQuery.fetch(in: $0) }
    #expect(current.exercises.map(\.key) == ["bench"])
    #expect(current.retiredExercises.map(\.key) == ["old-row"])
    #expect(current.workouts.first?.exerciseKeys == ["bench"])
  }
}
