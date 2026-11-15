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

  @Test func currentProgramQueryDeduplicatesRowsWithoutWriting() throws {
    let database = try DatabaseQueue()
    try FitHappensDatabaseMigrations.makeMigrator().migrate(database)
    let exerciseID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let duplicateExerciseID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
    let workoutID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
    let duplicateWorkoutID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000004"))
    let itemID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000005"))
    let duplicateItemID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000006"))
    let exercise = Exercise(
      id: exerciseID, key: "bench", name: "Bench", loadKind: .weight, currentLoadPounds: 135
    )
    let duplicateExercise = Exercise(
      id: duplicateExerciseID, key: "bench", name: "Bench copy", loadKind: .weight, currentLoadPounds: 145
    )
    let workout = Workout(id: workoutID, key: "A", position: 0)
    let duplicateWorkout = Workout(id: duplicateWorkoutID, key: "A", position: 1)
    try insertDuplicates(
      database,
      exercises: [exercise, duplicateExercise],
      workouts: [workout, duplicateWorkout],
      items: [
        WorkoutItem(
          id: itemID, workoutID: workoutID, exerciseID: exerciseID,
          position: 0, prescription: "3 × 5"
        ),
        WorkoutItem(
          id: duplicateItemID, workoutID: duplicateWorkoutID, exerciseID: duplicateExerciseID,
          position: 1, prescription: "4 × 8"
        )
      ]
    )

    let current = try database.read { try CurrentProgramQuery.fetch(in: $0) }
    let storedCounts = try database.read { connection in
      (
        try Exercise.all.fetchAll(connection).count,
        try Workout.all.fetchAll(connection).count,
        try WorkoutItem.all.fetchAll(connection).count
      )
    }

    #expect(current.exercises.map(\.key) == ["bench"])
    #expect(current.exercises.first?.load == .weight(pounds: 135))
    #expect(current.workouts.map(\.key) == ["A"])
    #expect(current.workouts.first?.exerciseKeys == ["bench"])
    #expect(current.workouts.first?.prescriptions["bench"] == "3 × 5")
    #expect(storedCounts.0 == 2)
    #expect(storedCounts.1 == 2)
    #expect(storedCounts.2 == 2)
  }
}

private func insertDuplicates(
  _ database: DatabaseQueue, exercises: [Exercise], workouts: [Workout], items: [WorkoutItem]
) throws {
  try database.write { connection in
    try Exercise.insert { exercises.map(Exercise.Draft.init) }.execute(connection)
    try Workout.insert { workouts.map(Workout.Draft.init) }.execute(connection)
    try WorkoutItem.insert { items.map(WorkoutItem.Draft.init) }.execute(connection)
  }
}
