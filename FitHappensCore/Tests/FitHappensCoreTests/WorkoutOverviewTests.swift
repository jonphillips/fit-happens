@testable import FitHappensCore
import Foundation
import SQLiteData
import Testing

struct WorkoutOverviewTests {
  @Test func overviewUsesCanonicalProgramAndOmitsRetiredExercises() throws {
    let chosenBenchID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let duplicateBenchID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let bench = Exercise(
      id: chosenBenchID, key: "bench", name: "Bench", loadKind: .weight,
      currentLoadPounds: 135, increment: nil
    )
    let duplicateBench = Exercise(
      id: duplicateBenchID, key: "bench", name: "Duplicate bench", loadKind: .weight,
      currentLoadPounds: 99, increment: 2.5
    )
    let retired = Exercise(
      id: UUID(), key: "retired", name: "Retired lift", loadKind: .weight,
      currentLoadPounds: 45, isRetired: true
    )
    let workoutA = Workout(id: UUID(), key: "A", position: 0)
    let workoutB = Workout(id: UUID(), key: "B", position: 1)
    let rows = [
      WorkoutItem(
        id: uuid(40), workoutID: workoutA.id, exerciseID: duplicateBench.id, position: 0, prescription: "3 × 5"
      ),
      WorkoutItem(id: uuid(41), workoutID: workoutA.id, exerciseID: bench.id, position: 1, prescription: "4 × 5"),
      WorkoutItem(id: UUID(), workoutID: workoutA.id, exerciseID: retired.id, position: 2, prescription: "2 × 10")
    ]
    let program = try CurrentProgramQuery.make(
      exerciseRows: [duplicateBench, retired, bench], workoutRows: [workoutB, workoutA], itemRows: rows
    )
    let overview = WorkoutOverview.make(program: program, latestCompletion: nil)

    #expect(overview?.workoutKey == "A")
    #expect(overview?.exercises.map(\.key) == ["bench"])
    #expect(overview?.exercises.first?.name == "Bench")
    #expect(overview?.exercises.first?.prescription == "3 × 5")
    #expect(overview?.exercises.first?.increment == nil)
  }

  @Test func defaultStepUpdatesStoredWeightAndCompletionReadsThatWeight() throws {
    let database = try DatabaseQueue()
    try FitHappensDatabaseMigrations.makeMigrator().migrate(database)
    let exercise = Exercise(
      id: UUID(), key: "bench", name: "Bench", loadKind: .weight, currentLoadPounds: 0
    )
    let workout = Workout(id: UUID(), key: "A", position: 0)
    try database.write { connection in
      try Exercise.insert { Exercise.Draft(exercise) }.execute(connection)
      try Workout.insert { Workout.Draft(workout) }.execute(connection)
      try WorkoutItem.insert {
        WorkoutItem.Draft(WorkoutItem(
          id: UUID(), workoutID: workout.id, exerciseID: exercise.id, position: 0, prescription: "3 × 5"
        ))
      }.execute(connection)
    }

    let snapshot = try database.write { connection in
      try WorkoutHistoryOperations.stepLoad(
        exerciseID: exercise.id, direction: 1, configuredIncrement: nil, in: connection
      )
      try WorkoutHistoryOperations.stepLoad(
        exerciseID: exercise.id, direction: 1, configuredIncrement: nil, in: connection
      )
      return try WorkoutHistoryOperations.complete(
        workoutKey: "A", at: Date(timeIntervalSince1970: 100), completionID: UUID(), makeID: UUID.init,
        in: connection
      )
    }

    #expect(WorkoutLoad.defaultIncrementPounds == 5)
    #expect(snapshot.items.first?.load == .weight(pounds: 10))
    let storedItem = try database.read { connection in
      try CompletionItem.all.fetchAll(connection).first
    }
    #expect(storedItem?.loadPounds == 10)
    #expect(storedItem?.prescription == "3 × 5")
  }

  @Test func undoLatestCompletionMovesRotationBack() throws {
    let database = try databaseWithTwoWorkouts()
    try database.write { connection in
      try WorkoutHistoryOperations.complete(
        workoutKey: "A", at: Date(timeIntervalSince1970: 100), completionID: uuid(1), makeID: { uuid(11) },
        in: connection
      )
      try WorkoutHistoryOperations.complete(
        workoutKey: "B", at: Date(timeIntervalSince1970: 200), completionID: uuid(2), makeID: { uuid(12) },
        in: connection
      )
    }
    #expect(try currentOverview(in: database)?.workoutKey == "A")

    try database.write { connection in
      try WorkoutHistoryOperations.undo(uuid(2), in: connection)
    }
    #expect(try currentOverview(in: database)?.workoutKey == "B")
  }

  @Test func correctingLatestCompletionEarlierChangesRotation() throws {
    let database = try databaseWithTwoWorkouts()
    try database.write { connection in
      try WorkoutHistoryOperations.complete(
        workoutKey: "A", at: Date(timeIntervalSince1970: 100), completionID: uuid(1), makeID: { uuid(11) },
        in: connection
      )
      try WorkoutHistoryOperations.complete(
        workoutKey: "B", at: Date(timeIntervalSince1970: 200), completionID: uuid(2), makeID: { uuid(12) },
        in: connection
      )
    }
    #expect(try currentOverview(in: database)?.workoutKey == "A")

    try database.write { connection in
      try WorkoutHistoryOperations.correctDate(
        Date(timeIntervalSince1970: 50), completionID: uuid(2), in: connection
      )
    }
    #expect(try currentOverview(in: database)?.workoutKey == "B")
  }
}

private func databaseWithTwoWorkouts() throws -> DatabaseQueue {
  let database = try DatabaseQueue()
  try FitHappensDatabaseMigrations.makeMigrator().migrate(database)
  let exercise = Exercise(id: uuid(20), key: "lift", name: "Lift", loadKind: .weight, currentLoadPounds: 10)
  let workoutA = Workout(id: uuid(21), key: "A", position: 0)
  let workoutB = Workout(id: uuid(22), key: "B", position: 1)
  try database.write { connection in
    try Exercise.insert { Exercise.Draft(exercise) }.execute(connection)
    try Workout.insert { [workoutA, workoutB].map(Workout.Draft.init) }.execute(connection)
    try WorkoutItem.insert {
      [workoutA, workoutB].enumerated().map { position, workout in
        WorkoutItem.Draft(WorkoutItem(
          id: uuid(30 + position), workoutID: workout.id, exerciseID: exercise.id,
          position: 0, prescription: "3 × 5"
        ))
      }
    }.execute(connection)
  }
  return database
}

private func currentOverview(in database: DatabaseQueue) throws -> WorkoutOverview? {
  try database.read { connection in
    let program = try CurrentProgramQuery.fetch(in: connection)
    let latest = CompletionSummary.latest(in: try Completion.all.fetchAll(connection).map {
      CompletionSummary(id: $0.id, workoutKey: $0.workoutKey, completedAt: $0.completedAt)
    })
    return WorkoutOverview.make(program: program, latestCompletion: latest)
  }
}

private func uuid(_ value: Int) -> UUID {
  UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
}
