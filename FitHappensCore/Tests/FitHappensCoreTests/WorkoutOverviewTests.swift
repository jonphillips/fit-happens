@testable import FitHappensCore
import Foundation
import SQLiteData
import Testing

struct WorkoutOverviewTests {
  @Test func overviewOrdersExercisesAndAdvancesAfterCompletion() throws {
    let bench = Exercise(
      id: UUID(), key: "bench", name: "Bench", loadKind: .weight,
      currentLoadPounds: 135, increment: 5
    )
    let row = Exercise(id: UUID(), key: "row", name: "Row", loadKind: .weight, currentLoadPounds: 90)
    let bodyweight = Exercise(id: UUID(), key: "plank", name: "Plank", loadKind: .bodyweight)
    let workoutA = Workout(id: UUID(), key: "A", position: 0)
    let workoutB = Workout(id: UUID(), key: "B", position: 1)
    let items = [
      WorkoutItem(id: UUID(), workoutID: workoutA.id, exerciseID: bench.id, position: 1, prescription: "3 × 5"),
      WorkoutItem(id: UUID(), workoutID: workoutA.id, exerciseID: bodyweight.id, position: 2, prescription: "3 × 30s"),
      WorkoutItem(id: UUID(), workoutID: workoutA.id, exerciseID: row.id, position: 0, prescription: "3 × 8")
    ]
    let first = WorkoutOverview.make(
      workouts: [workoutA, workoutB], items: items, exercises: [bench, row, bodyweight], completions: []
    )
    #expect(first?.workoutKey == "A")
    #expect(first?.exercises.map(\.key) == ["row", "bench", "plank"])
    #expect(first?.exercises[1].load == .weight(pounds: 135))
    #expect(first?.exercises[2].loadKind == .bodyweight)

    let completion = Completion(id: UUID(), workoutKey: "A", completedAt: Date(timeIntervalSince1970: 10))
    let next = WorkoutOverview.make(
      workouts: [workoutA, workoutB], items: items, exercises: [bench, row, bodyweight], completions: [completion]
    )
    #expect(next?.workoutKey == "B")
    #expect(next?.lastCompletedAt == completion.completedAt)
  }

  @Test func completionSnapshotIsIndependentAndCorrectionsUpdateHistory() throws {
    let database = try DatabaseQueue()
    try FitHappensDatabaseMigrations.makeMigrator().migrate(database)
    let exercise = Exercise(
      id: UUID(), key: "bench", name: "Bench", loadKind: .weight,
      currentLoadPounds: 135, increment: 5
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
    let snapshot = try CompletionSnapshots.make(
      workout: CurrentWorkout(key: "A", exerciseKeys: ["bench"], prescriptions: ["bench": "3 × 5"]),
      exercises: [CurrentExercise(
        key: "bench", name: "Bench", loadKind: .weight, load: .weight(pounds: 135), increment: 5
      )],
      completedAt: Date(timeIntervalSince1970: 100), completionID: UUID(), makeID: UUID.init
    )
    try database.write { connection in
      try WorkoutHistoryOperations.save(snapshot, exerciseIDsByKey: ["bench": exercise.id], in: connection)
      try WorkoutHistoryOperations.setLoad(140, exerciseID: exercise.id, in: connection)
      try WorkoutHistoryOperations.correctDate(
        Date(timeIntervalSince1970: 50), completionID: snapshot.id, in: connection
      )
    }
    let saved = try database.read { connection in
      (try Completion.find(snapshot.id).fetchOne(connection),
       try CompletionItem.all.fetchAll(connection).first,
       try Exercise.find(exercise.id).fetchOne(connection))
    }
    #expect(saved.0?.completedAt == Date(timeIntervalSince1970: 50))
    #expect(saved.1?.loadPounds == 135)
    #expect(saved.1?.prescription == "3 × 5")
    #expect(saved.2?.currentLoadPounds == 140)

    try database.write { connection in
      try WorkoutHistoryOperations.undo(snapshot.id, in: connection)
    }
    let counts = try database.read { connection in
      (try Completion.all.fetchAll(connection).count, try CompletionItem.all.fetchAll(connection).count)
    }
    #expect(counts.0 == 0)
    #expect(counts.1 == 0)
  }
}
