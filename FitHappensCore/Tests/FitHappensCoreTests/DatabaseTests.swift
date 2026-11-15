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

  @Test func currentProgramQueryDeduplicatesWithoutWritingThenApplyConverges() throws {
    let database = try DatabaseQueue()
    try FitHappensDatabaseMigrations.makeMigrator().migrate(database)
    let fixture = try seedDuplicateRows(in: database)

    let current = try database.read { try CurrentProgramQuery.fetch(in: $0) }
    let storedCounts = try database.read { connection in
      (
        try Exercise.all.fetchAll(connection).count,
        try Workout.all.fetchAll(connection).count,
        try WorkoutItem.all.fetchAll(connection).count,
        try CompletionItem.all.fetchAll(connection).count
      )
    }

    #expect(current.exercises.map(\.key) == ["bench"])
    #expect(current.exercises.first?.load == .weight(pounds: 135))
    #expect(current.workouts.map(\.key) == ["A"])
    #expect(current.workouts.first?.exerciseKeys == ["bench"])
    #expect(current.workouts.first?.prescriptions["bench"] == "4 × 8")
    #expect(storedCounts.0 == 2)
    #expect(storedCounts.1 == 2)
    #expect(storedCounts.2 == 2)
    #expect(storedCounts.3 == 1)

    try assertApplyConverges(database, fixture: fixture)
  }
}

private struct DuplicateRowFixture {
  var exerciseID: UUID
  var workoutID: UUID
  var itemID: UUID
  var completionID: UUID
  var completionItemID: UUID
}

private func seedDuplicateRows(in database: DatabaseQueue) throws -> DuplicateRowFixture {
  let exerciseID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
  let duplicateExerciseID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
  let workoutID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
  let duplicateWorkoutID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000004"))
  let itemID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000005"))
  let duplicateItemID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000006"))
  let completionID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000007"))
  let completionItemID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000008"))
  try insertDuplicates(
    database,
    exercises: [
      Exercise(id: exerciseID, key: "bench", name: "Bench", loadKind: .weight, currentLoadPounds: 135),
      Exercise(
        id: duplicateExerciseID, key: "bench", name: "Bench copy", loadKind: .weight,
        currentLoadPounds: 145
      )
    ],
    workouts: [Workout(id: workoutID, key: "A", position: 0), Workout(id: duplicateWorkoutID, key: "A", position: 1)],
    items: [
      WorkoutItem(
        id: itemID, workoutID: duplicateWorkoutID, exerciseID: duplicateExerciseID,
        position: 1, prescription: "4 × 8"
      ),
      WorkoutItem(
        id: duplicateItemID, workoutID: workoutID, exerciseID: exerciseID,
        position: 0, prescription: "3 × 5"
      )
    ]
  )
  try insertCompletionReference(
    in: database, completionID: completionID, completionItemID: completionItemID,
    exerciseID: duplicateExerciseID
  )
  return DuplicateRowFixture(
    exerciseID: exerciseID, workoutID: workoutID, itemID: itemID,
    completionID: completionID, completionItemID: completionItemID
  )
}

private func assertApplyConverges(_ database: DatabaseQueue, fixture: DuplicateRowFixture) throws {
  let programText = """
  FH-PROGRAM: v1
  {"workouts":[{"key":"A","items":[{"key":"bench","name":"Bench press","prescription":"3 × 5","loadKind":"weight"}]}]}
  """
  _ = try ProgramApplication.apply(programText: programText, to: database)
  let records = try database.read { connection in
    (
      try Exercise.all.fetchAll(connection),
      try Workout.all.fetchAll(connection),
      try WorkoutItem.all.fetchAll(connection),
      try CompletionItem.all.fetchAll(connection),
      try ProgramRevision.all.fetchAll(connection)
    )
  }
  #expect(records.0.count == 1)
  #expect(records.0.first?.id == fixture.exerciseID)
  #expect(records.0.first?.currentLoadPounds == 135)
  #expect(records.1.count == 1)
  #expect(records.1.first?.id == fixture.workoutID)
  #expect(records.2.count == 1)
  #expect(records.2.first?.id == fixture.itemID)
  #expect(records.2.first?.workoutID == fixture.workoutID)
  #expect(records.2.first?.exerciseID == fixture.exerciseID)
  #expect(records.2.first?.prescription == "3 × 5")
  #expect(records.3.count == 1)
  #expect(records.3.first?.id == fixture.completionItemID)
  #expect(records.3.first?.completionID == fixture.completionID)
  #expect(records.3.first?.exerciseID == fixture.exerciseID)
  #expect(records.4.count == 1)
}

private func insertCompletionReference(
  in database: DatabaseQueue, completionID: UUID, completionItemID: UUID, exerciseID: UUID
) throws {
  try database.write { connection in
    try Completion.insert {
      Completion.Draft(Completion(id: completionID, workoutKey: "A", completedAt: Date(timeIntervalSince1970: 1)))
    }.execute(connection)
    try CompletionItem.insert {
      CompletionItem.Draft(CompletionItem(
        id: completionItemID, completionID: completionID, exerciseID: exerciseID,
        position: 0, name: "Bench copy", prescription: "3 × 5", loadKind: .weight, loadPounds: 145
      ))
    }.execute(connection)
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
