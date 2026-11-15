import Foundation
import SQLiteData

public enum ProgramApplicationError: Error, Equatable, Sendable {
  case duplicateExerciseKey(String)
  case duplicateWorkoutKey(String)
  case duplicateWorkoutItem(workout: String, exercise: String)
  case invalidWeight(String)
}

public enum ProgramApplication {
  private struct ItemIdentity: Hashable {
    var workoutID: Workout.ID
    var exerciseID: Exercise.ID
  }

  private struct ExistingRows {
    var exercises: [Exercise]
    var exercisesByKey: [String: Exercise]
    var workouts: [Workout]
    var workoutsByKey: [String: Workout]
    var items: [WorkoutItem]
    var itemsByIdentity: [ItemIdentity: WorkoutItem]

    init(in database: Database) throws {
      exercises = try Exercise.all.fetchAll(database)
      exercisesByKey = try ProgramApplication.uniqueRows(exercises, key: \.key) {
        ProgramApplicationError.duplicateExerciseKey($0)
      }
      workouts = try Workout.all.fetchAll(database)
      workoutsByKey = try ProgramApplication.uniqueRows(workouts, key: \.key) {
        ProgramApplicationError.duplicateWorkoutKey($0)
      }
      items = try WorkoutItem.all.fetchAll(database)
      var byIdentity: [ItemIdentity: WorkoutItem] = [:]
      for item in items {
        let identity = ItemIdentity(workoutID: item.workoutID, exerciseID: item.exerciseID)
        guard byIdentity.updateValue(item, forKey: identity) == nil else {
          let workoutKey = workouts.first { $0.id == item.workoutID }?.key ?? item.workoutID.uuidString
          let exerciseKey = exercises.first { $0.id == item.exerciseID }?.key ?? item.exerciseID.uuidString
          throw ProgramApplicationError.duplicateWorkoutItem(workout: workoutKey, exercise: exerciseKey)
        }
      }
      itemsByIdentity = byIdentity
    }
  }

  public static func apply(
    programText: String,
    to database: any DatabaseWriter,
    acceptedAt: Date = .now
  ) throws -> ProgramChangeSet {
    let contract = try ProgramContractDecoder.decode(programText).contract
    return try database.write { database in
      try apply(contract: contract, programText: programText, acceptedAt: acceptedAt, in: database)
    }
  }

  private static func apply(
    contract: ProgramContract, programText: String, acceptedAt: Date, in database: Database
  ) throws -> ProgramChangeSet {
    let current = try CurrentProgramQuery.fetch(in: database)
    let changes = try ProgramChanges.make(current: current, proposal: contract)
    let existing = try ExistingRows(in: database)
    let exerciseIDs = try upsertExercises(contract, existing: existing, in: database)
    let workoutIDs = try upsertWorkouts(contract, existing: existing.workoutsByKey, in: database)
    let desiredItems = desiredWorkoutItems(contract, exerciseIDs: exerciseIDs, workoutIDs: workoutIDs)
    try reconcileWorkoutItems(desiredItems, existing: existing, in: database)
    try deleteRemovedWorkouts(contract, existing: existing.workouts, in: database)
    try insertRevision(programText, acceptedAt: acceptedAt, in: database)
    return changes
  }

  private static func upsertExercises(
    _ contract: ProgramContract, existing: ExistingRows, in database: Database
  ) throws -> [String: Exercise.ID] {
    var definitions: [String: ProgramExercise] = [:]
    for item in contract.workouts.flatMap(\.items) where definitions[item.key] == nil {
      definitions[item.key] = item
    }
    var ids: [String: Exercise.ID] = [:]
    for item in definitions.values {
      let old = existing.exercisesByKey[item.key]
      let loadPounds = try loadPounds(for: item, previous: old)
      let exercise = Exercise(
        id: old?.id ?? UUID(), key: item.key, name: item.name, loadKind: item.loadKind,
        currentLoadPounds: loadPounds, increment: item.increment,
        loadLabel: item.loadLabel, notes: item.notes, isRetired: false
      )
      try Exercise.upsert { Exercise.Draft(exercise) }.execute(database)
      ids[item.key] = exercise.id
    }
    let proposedKeys = Set(definitions.keys)
    for var exercise in existing.exercises where !exercise.isRetired && !proposedKeys.contains(exercise.key) {
      exercise.isRetired = true
      try Exercise.upsert { Exercise.Draft(exercise) }.execute(database)
    }
    return ids
  }

  private static func loadPounds(for item: ProgramExercise, previous: Exercise?) throws -> Double? {
    switch item.loadKind {
    case .bodyweight:
      return nil
    case .weight:
      if let previous, previous.loadKind == .weight {
        guard let currentLoad = previous.currentLoadPounds else {
          throw ProgramApplicationError.invalidWeight(item.key)
        }
        return currentLoad
      }
      guard let startingWeight = item.startingWeight else {
        throw ProgramApplicationError.invalidWeight(item.key)
      }
      return startingWeight
    }
  }

  private static func upsertWorkouts(
    _ contract: ProgramContract, existing: [String: Workout], in database: Database
  ) throws -> [String: Workout.ID] {
    var ids: [String: Workout.ID] = [:]
    for (position, workout) in contract.workouts.enumerated() {
      let record = Workout(id: existing[workout.key]?.id ?? UUID(), key: workout.key, position: position)
      try Workout.upsert { Workout.Draft(record) }.execute(database)
      ids[workout.key] = record.id
    }
    return ids
  }

  private static func desiredWorkoutItems(
    _ contract: ProgramContract, exerciseIDs: [String: Exercise.ID], workoutIDs: [String: Workout.ID]
  ) -> [ItemIdentity: (position: Int, prescription: String)] {
    var desired: [ItemIdentity: (position: Int, prescription: String)] = [:]
    for workout in contract.workouts {
      guard let workoutID = workoutIDs[workout.key] else { continue }
      for (position, exercise) in workout.items.enumerated() {
        guard let exerciseID = exerciseIDs[exercise.key] else { continue }
        desired[ItemIdentity(workoutID: workoutID, exerciseID: exerciseID)] =
          (position, exercise.prescription)
      }
    }
    return desired
  }

  private static func reconcileWorkoutItems(
    _ desired: [ItemIdentity: (position: Int, prescription: String)],
    existing: ExistingRows,
    in database: Database
  ) throws {
    for item in existing.items {
      let identity = ItemIdentity(workoutID: item.workoutID, exerciseID: item.exerciseID)
      guard desired[identity] == nil else { continue }
      try WorkoutItem.find(item.id).delete().execute(database)
    }
    for (identity, value) in desired {
      let record = WorkoutItem(
        id: existing.itemsByIdentity[identity]?.id ?? UUID(), workoutID: identity.workoutID,
        exerciseID: identity.exerciseID, position: value.position, prescription: value.prescription
      )
      try WorkoutItem.upsert { WorkoutItem.Draft(record) }.execute(database)
    }
  }

  private static func deleteRemovedWorkouts(
    _ contract: ProgramContract, existing: [Workout], in database: Database
  ) throws {
    let proposedKeys = Set(contract.workouts.map(\.key))
    for workout in existing where !proposedKeys.contains(workout.key) {
      try Workout.find(workout.id).delete().execute(database)
    }
  }

  private static func insertRevision(_ text: String, acceptedAt: Date, in database: Database) throws {
    let revision = ProgramRevision(id: UUID(), acceptedAt: acceptedAt, contractText: text)
    try ProgramRevision.insert { ProgramRevision.Draft(revision) }.execute(database)
  }

  private static func uniqueRows<Row, Key: Hashable>(
    _ rows: [Row], key: (Row) -> Key, duplicateError: (Key) -> ProgramApplicationError
  ) throws -> [Key: Row] {
    var result: [Key: Row] = [:]
    for row in rows {
      let rowKey = key(row)
      guard result.updateValue(row, forKey: rowKey) == nil else { throw duplicateError(rowKey) }
    }
    return result
  }
}
