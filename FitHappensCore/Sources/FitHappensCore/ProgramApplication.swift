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

  private struct DesiredWorkoutItem {
    var position: Int
    var prescription: String
    var ramp: String?
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
    acceptedAt: Date = .now,
    isStoredRevision: Bool = false
  ) throws -> ProgramChangeSet {
    let contract = try ProgramContractDecoder.decode(programText).contract
    return try database.write { database in
      try convergeDuplicateRows(in: database)
      return try apply(
        contract: contract, programText: programText, acceptedAt: acceptedAt,
        isStoredRevision: isStoredRevision, in: database
      )
    }
  }

  private static func convergeDuplicateRows(in database: Database) throws {
    let exercises = try Exercise.all.fetchAll(database)
    let exerciseWinners = canonicalRows(exercises, key: \.key, id: \.id)
    let exerciseIDByRowID = Dictionary(uniqueKeysWithValues: exercises.compactMap { row in
      exerciseWinners[row.key].map { (row.id, $0.id) }
    })
    let workouts = try Workout.all.fetchAll(database)
    let workoutWinners = canonicalRows(workouts, key: \.key, id: \.id)
    let workoutIDByRowID = Dictionary(uniqueKeysWithValues: workouts.compactMap { row in
      workoutWinners[row.key].map { (row.id, $0.id) }
    })

    let existingItems = try WorkoutItem.all.fetchAll(database)
    let itemGroups = Dictionary(grouping: existingItems) { item in
      ItemIdentity(
        workoutID: workoutIDByRowID[item.workoutID] ?? item.workoutID,
        exerciseID: exerciseIDByRowID[item.exerciseID] ?? item.exerciseID
      )
    }
    let itemWinners = itemGroups.values.compactMap { items in
      items.min { $0.id.uuidString < $1.id.uuidString }
    }
    let survivingItemIDs = Set(itemWinners.map(\.id))
    for var item in itemWinners {
      let originalWorkoutID = item.workoutID
      let originalExerciseID = item.exerciseID
      item.workoutID = workoutIDByRowID[originalWorkoutID] ?? originalWorkoutID
      item.exerciseID = exerciseIDByRowID[originalExerciseID] ?? originalExerciseID
      guard item.workoutID != originalWorkoutID || item.exerciseID != originalExerciseID else { continue }
      try WorkoutItem.upsert { WorkoutItem.Draft(item) }.execute(database)
    }

    for var completionItem in try CompletionItem.all.fetchAll(database) {
      guard let canonicalExerciseID = exerciseIDByRowID[completionItem.exerciseID],
            canonicalExerciseID != completionItem.exerciseID
      else { continue }
      completionItem.exerciseID = canonicalExerciseID
      try CompletionItem.upsert { CompletionItem.Draft(completionItem) }.execute(database)
    }

    for item in existingItems where !survivingItemIDs.contains(item.id) {
      try WorkoutItem.find(item.id).delete().execute(database)
    }
    let exerciseLosers = exercises.filter { exerciseWinners[$0.key]?.id != $0.id }
    let workoutLosers = workouts.filter { workoutWinners[$0.key]?.id != $0.id }
    // References are repointed before parent deletion; ON DELETE CASCADE relies on foreign keys being on.
    for exercise in exerciseLosers {
      try Exercise.find(exercise.id).delete().execute(database)
    }
    for workout in workoutLosers {
      try Workout.find(workout.id).delete().execute(database)
    }
  }

  private static func apply(
    contract: ProgramContract, programText: String, acceptedAt: Date,
    isStoredRevision: Bool, in database: Database
  ) throws -> ProgramChangeSet {
    let current = try CurrentProgramQuery.fetch(in: database)
    let changes = try ProgramChanges.make(current: current, proposal: contract, isStoredRevision: isStoredRevision)
    let existing = try ExistingRows(in: database)
    let exerciseIDs = try upsertExercises(
      contract, existing: existing, isStoredRevision: isStoredRevision, in: database
    )
    let workoutIDs = try upsertWorkouts(contract, existing: existing.workoutsByKey, in: database)
    let desiredItems = desiredWorkoutItems(contract, exerciseIDs: exerciseIDs, workoutIDs: workoutIDs)
    try reconcileWorkoutItems(desiredItems, existing: existing, in: database)
    try deleteRemovedWorkouts(contract, existing: existing.workouts, in: database)
    try insertRevision(programText, acceptedAt: acceptedAt, in: database)
    return changes
  }

  private static func upsertExercises(
    _ contract: ProgramContract, existing: ExistingRows,
    isStoredRevision: Bool, in database: Database
  ) throws -> [String: Exercise.ID] {
    var definitions: [String: ProgramExercise] = [:]
    for item in contract.workouts.flatMap(\.items) where definitions[item.key] == nil {
      definitions[item.key] = item
    }
    var ids: [String: Exercise.ID] = [:]
    for item in definitions.values {
      let old = existing.exercisesByKey[item.key]
      let loadPounds = try loadPounds(for: item, previous: old, isStoredRevision: isStoredRevision)
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

  private static func loadPounds(
    for item: ProgramExercise, previous: Exercise?, isStoredRevision: Bool
  ) throws -> Double? {
    switch item.loadKind {
    case .bodyweight:
      return nil
    case .weight:
      if let previous, previous.loadKind == .weight {
        guard let currentLoad = previous.currentLoadPounds else {
          throw ProgramApplicationError.invalidWeight(item.key)
        }
        return isStoredRevision ? currentLoad : (item.newWeight ?? currentLoad)
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
  ) -> [ItemIdentity: DesiredWorkoutItem] {
    var desired: [ItemIdentity: DesiredWorkoutItem] = [:]
    for workout in contract.workouts {
      guard let workoutID = workoutIDs[workout.key] else { continue }
      for (position, exercise) in workout.items.enumerated() {
        guard let exerciseID = exerciseIDs[exercise.key] else { continue }
        let ramp = exercise.ramp.flatMap { try? JSONEncoder().encode($0) }
          .map { String(decoding: $0, as: UTF8.self) }
        desired[ItemIdentity(workoutID: workoutID, exerciseID: exerciseID)] = DesiredWorkoutItem(
          position: position, prescription: exercise.prescription, ramp: ramp
        )
      }
    }
    return desired
  }

  private static func reconcileWorkoutItems(
    _ desired: [ItemIdentity: DesiredWorkoutItem],
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
        exerciseID: identity.exerciseID, position: value.position, prescription: value.prescription,
        ramp: value.ramp
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

  private static func canonicalRows<Row, Key: Hashable>(
    _ rows: [Row], key: (Row) -> Key, id: (Row) -> UUID
  ) -> [Key: Row] {
    Dictionary(grouping: rows, by: key).compactMapValues { candidates in
      candidates.min { id($0).uuidString < id($1).uuidString }
    }
  }
}
