@testable import FitHappensCore
import Foundation
import SQLiteData
import Testing

struct ProgramApplicationTests {
  @Test func firstImportCreatesCurrentRowsAndOneRevision() throws {
    let database = try makeDatabase()
    let text = try programText([
      ProgramWorkout(key: "A", items: [
        ProgramExercise(
          key: "bench", name: "Bench press", prescription: "3 × 5", loadKind: .weight,
          startingWeight: 135
        )
      ])
    ])

    let changes = try ProgramApplication.apply(
      programText: text, to: database, acceptedAt: Date(timeIntervalSince1970: 1)
    )
    let state = try storedState(database)

    #expect(changes.addedExercises.map(\.key) == ["bench"])
    #expect(state.exercises.map(\.key) == ["bench"])
    #expect(state.exercises.first?.currentLoadPounds == 135)
    #expect(state.workouts.map(\.key) == ["A"])
    #expect(state.items.count == 1)
    #expect(state.revisions.count == 1)
    #expect(state.revisions.first?.contractText == text)
  }

  @Test func reapplyingStoredRevisionKeepsChangedWeightsAndReportsIgnoredValues() throws {
    let database = try makeDatabase()
    let fixtureURL = try #require(
      Bundle.module.url(forResource: "real-program", withExtension: "json", subdirectory: "Fixtures")
    )
    let originalText = try String(contentsOf: fixtureURL, encoding: .utf8)
    _ = try ProgramApplication.apply(programText: originalText, to: database)
    let storedText = try #require(try storedState(database).revisions.first?.contractText)
    try database.write { connection in
      let row = try #require(try Exercise.all.fetchAll(connection).first { $0.key == "low-cable-row" })
      var changed = row
      changed.currentLoadPounds = 155
      try Exercise.upsert { Exercise.Draft(changed) }.execute(connection)
    }

    let changes = try ProgramApplication.apply(programText: storedText, to: database)
    let state = try storedState(database)
    let row = try #require(state.exercises.first { $0.key == "low-cable-row" })

    #expect(row.currentLoadPounds == 155)
    #expect(changes.carriedWeights.contains(WeightCarryover(
      exerciseKey: "low-cable-row", load: .weight(pounds: 155)
    )))
    #expect(changes.ignoredStartingWeights.contains(IgnoredStartingWeight(
      exerciseKey: "low-cable-row", proposedPounds: 0, keptLoad: .weight(pounds: 155)
    )))
    #expect(state.revisions.count == 2)
    #expect(state.revisions.contains { $0.contractText == storedText })
  }

  @Test func replacementPreservesIdentityAndReconcilesProgram() throws {
    let database = try makeDatabase()
    let before = try seedPriorState(database)
    let replacement = try replacementText()
    let changes = try ProgramApplication.apply(
      programText: replacement, to: database, acceptedAt: Date(timeIntervalSince1970: 3)
    )
    let after = try storedState(database)
    let exercises = Dictionary(uniqueKeysWithValues: after.exercises.map { ($0.key, $0) })
    let workouts = Dictionary(uniqueKeysWithValues: after.workouts.map { ($0.key, $0) })

    assertChangeSummary(changes)
    assertExerciseIdentityAndLoads(exercises, previous: before.exerciseIDs)
    assertWorkoutIdentityAndItems(after, workouts: workouts, previous: before, exercises: exercises)
    #expect(after.revisions.count == before.revisionCount + 1)
    #expect(after.revisions.contains { $0.contractText == replacement })
  }

  @Test func proposalChangesKnownWorkingWeight() throws {
    let database = try makeDatabase()
    let original = try programText([ProgramWorkout(key: "A", items: [
      ProgramExercise(key: "bench", name: "Bench", prescription: "3 × 5", loadKind: .weight, startingWeight: 135)
    ])])
    _ = try ProgramApplication.apply(programText: original, to: database)
    let proposal = try programText([ProgramWorkout(key: "A", items: [
      ProgramExercise(key: "bench", name: "Bench", prescription: "3 × 5", loadKind: .weight, newWeight: 145)
    ])])
    let changes = try ProgramApplication.apply(programText: proposal, to: database)
    let state = try storedState(database)
    #expect(changes.weightChanges == [WeightChange(exerciseKey: "bench", oldPounds: 135, newPounds: 145)])
    #expect(state.exercises.first?.currentLoadPounds == 145)
  }

  @Test func reapplyingStoredRevisionIgnoresNewWeight() throws {
    let database = try makeDatabase()
    let original = try programText([ProgramWorkout(key: "A", items: [
      ProgramExercise(key: "bench", name: "Bench", prescription: "3 × 5", loadKind: .weight, startingWeight: 135)
    ])])
    _ = try ProgramApplication.apply(programText: original, to: database)
    let proposal = try programText([ProgramWorkout(key: "A", items: [
      ProgramExercise(key: "bench", name: "Bench", prescription: "3 × 5", loadKind: .weight, newWeight: 145)
    ])])
    _ = try ProgramApplication.apply(programText: proposal, to: database)
    let changes = try ProgramApplication.apply(programText: proposal, to: database, isStoredRevision: true)
    let row = try #require(try storedState(database).exercises.first)
    #expect(row.currentLoadPounds == 145)
    #expect(changes.weightChanges.isEmpty)
    #expect(changes.ignoredNewWeights == [IgnoredStartingWeight(
      exerciseKey: "bench", proposedPounds: 145, keptLoad: .weight(pounds: 145)
    )])
  }
}

private struct StoredProgram {
  var exercises: [Exercise]
  var workouts: [Workout]
  var items: [WorkoutItem]
  var revisions: [ProgramRevision]
}

private struct PriorProgram {
  var exerciseIDs: [String: UUID]
  var workoutIDs: [String: UUID]
  var benchItemID: UUID
  var dipItemID: UUID
  var revisionCount: Int
}

private func seedPriorState(_ database: DatabaseQueue) throws -> PriorProgram {
  _ = try ProgramApplication.apply(programText: firstProgramText(), to: database)
  _ = try ProgramApplication.apply(programText: retirementProgramText(), to: database)
  let state = try storedState(database)
  let exerciseIDs = Dictionary(uniqueKeysWithValues: state.exercises.map { ($0.key, $0.id) })
  let workoutIDs = Dictionary(uniqueKeysWithValues: state.workouts.map { ($0.key, $0.id) })
  let bench = try #require(state.items.first {
    $0.workoutID == workoutIDs["A"] && $0.exerciseID == exerciseIDs["bench"]
  })
  let dip = try #require(state.items.first {
    $0.workoutID == workoutIDs["B"] && $0.exerciseID == exerciseIDs["dip"]
  })
  return PriorProgram(
    exerciseIDs: exerciseIDs, workoutIDs: workoutIDs, benchItemID: bench.id,
    dipItemID: dip.id, revisionCount: state.revisions.count
  )
}

private func assertChangeSummary(_ changes: ProgramChangeSet) {
  #expect(changes.renames.map(\.key) == ["bench", "bridge", "dip"])
  #expect(changes.retiredExerciseKeys == ["squat"])
  #expect(changes.restoredExerciseKeys == ["curl"])
  #expect(changes.removedWorkoutKeys == ["B"])
  #expect(changes.addedWorkouts.map(\.key) == ["C"])
}

private func assertExerciseIdentityAndLoads(_ exercises: [String: Exercise], previous: [String: UUID]) {
  #expect(exercises["bench"]?.id == previous["bench"])
  #expect(exercises["bridge"]?.id == previous["bridge"])
  #expect(exercises["curl"]?.id == previous["curl"])
  #expect(exercises["dip"]?.id == previous["dip"])
  #expect(exercises["squat"]?.id == previous["squat"])
  #expect(exercises["squat"]?.isRetired == true)
  #expect(exercises["bench"]?.currentLoadPounds == 135)
  #expect(exercises["curl"]?.currentLoadPounds == 35)
  #expect(exercises["bridge"]?.loadKind == .weight)
  #expect(exercises["bridge"]?.currentLoadPounds == 12)
  #expect(exercises["dip"]?.loadKind == .bodyweight)
  #expect(exercises["dip"]?.currentLoadPounds == nil)
  #expect(exercises["press-new"]?.currentLoadPounds == 20)
}

private func assertWorkoutIdentityAndItems(
  _ state: StoredProgram,
  workouts: [String: Workout],
  previous: PriorProgram,
  exercises: [String: Exercise]
) {
  #expect(workouts["A"]?.id == previous.workoutIDs["A"])
  #expect(workouts["B"] == nil)
  #expect(workouts["C"] != nil)
  #expect(state.items.allSatisfy { $0.workoutID != previous.workoutIDs["B"] })
  #expect(state.items.contains { $0.id == previous.benchItemID })
  #expect(!state.items.contains { $0.id == previous.dipItemID })
  #expect(state.items.contains {
    $0.workoutID == workouts["A"]?.id && $0.exerciseID == exercises["dip"]?.id
  })
}

private func makeDatabase() throws -> DatabaseQueue {
  let database = try DatabaseQueue()
  try FitHappensDatabaseMigrations.makeMigrator().migrate(database)
  return database
}

private func storedState(_ database: DatabaseQueue) throws -> StoredProgram {
  try database.read { connection in
    StoredProgram(
      exercises: try Exercise.all.fetchAll(connection),
      workouts: try Workout.all.fetchAll(connection),
      items: try WorkoutItem.all.fetchAll(connection),
      revisions: try ProgramRevision.all.fetchAll(connection)
    )
  }
}

private func firstProgramText() throws -> String {
  try programText([
    ProgramWorkout(key: "A", items: [
      ProgramExercise(
        key: "bench", name: "Bench press", prescription: "3 × 5", loadKind: .weight,
        startingWeight: 135
      ),
      ProgramExercise(key: "bridge", name: "Bridge", prescription: "2 × 10", loadKind: .bodyweight),
      ProgramExercise(
        key: "curl", name: "Cable curl", prescription: "2 × 12", loadKind: .weight,
        startingWeight: 35
      )
    ]),
    ProgramWorkout(key: "B", items: [
      ProgramExercise(
        key: "squat", name: "Squat", prescription: "3 × 5", loadKind: .weight,
        startingWeight: 95
      ),
      ProgramExercise(
        key: "dip", name: "Weighted dip", prescription: "3 × 8", loadKind: .weight,
        startingWeight: 25
      )
    ])
  ])
}

private func retirementProgramText() throws -> String {
  try programText([
    ProgramWorkout(key: "A", items: [
      ProgramExercise(key: "bench", name: "Bench press", prescription: "3 × 5", loadKind: .weight),
      ProgramExercise(key: "bridge", name: "Bridge", prescription: "2 × 10", loadKind: .bodyweight)
    ]),
    ProgramWorkout(key: "B", items: [
      ProgramExercise(key: "squat", name: "Squat", prescription: "3 × 5", loadKind: .weight),
      ProgramExercise(key: "dip", name: "Weighted dip", prescription: "3 × 8", loadKind: .weight)
    ])
  ])
}

private func replacementText() throws -> String {
  try programText([
    ProgramWorkout(key: "A", items: [
      ProgramExercise(
        key: "bench", name: "Flat bench press", prescription: "3 × 5–8", loadKind: .weight
      ),
      ProgramExercise(
        key: "bridge", name: "Weighted bridge", prescription: "3 × 8", loadKind: .weight,
        startingWeight: 12
      ),
      ProgramExercise(key: "dip", name: "Dip", prescription: "2 × 10", loadKind: .bodyweight),
      ProgramExercise(key: "curl", name: "Cable curl", prescription: "3 × 12", loadKind: .weight),
      ProgramExercise(
        key: "press-new", name: "Machine press", prescription: "2 × 10", loadKind: .weight,
        startingWeight: 20
      )
    ]),
    ProgramWorkout(key: "C", items: [
      ProgramExercise(key: "crunch", name: "Crunch", prescription: "2 × 15", loadKind: .bodyweight)
    ])
  ])
}

private func programText(_ workouts: [ProgramWorkout]) throws -> String {
  let data = try JSONEncoder().encode(ProgramContract(workouts: workouts))
  return "\(ProgramContractMarker.identifier)\n\(String(decoding: data, as: UTF8.self))"
}
