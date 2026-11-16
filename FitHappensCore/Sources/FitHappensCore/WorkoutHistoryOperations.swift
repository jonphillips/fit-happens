import Foundation
import SQLiteData

public enum WorkoutLoad {
  public static let defaultIncrementPounds = 5.0

  public static func incrementPounds(configuredIncrement: Double?) -> Double {
    configuredIncrement ?? defaultIncrementPounds
  }
}

public enum WorkoutHistoryOperations {
  public enum Error: Swift.Error {
    case missingWorkout(String)
    case missingExerciseID(String)
  }

  public static func setLoad(_ pounds: Double, exerciseID: Exercise.ID, in database: Database) throws {
    try Exercise.find(exerciseID).update { $0.currentLoadPounds = #bind(pounds) }.execute(database)
  }

  /// Applies a step to the stored load in SQL so rapid taps cannot use a stale observed value.
  public static func stepLoad(
    exerciseID: Exercise.ID, direction: Int, configuredIncrement: Double?, in database: Database
  ) throws {
    let step = Double(direction) * WorkoutLoad.incrementPounds(configuredIncrement: configuredIncrement)
    try #sql(
      """
      UPDATE "exercises"
      SET "currentLoadPounds" = max(0, coalesce("currentLoadPounds", 0) + \(#bind(step, as: Double.self)))
      WHERE "id" = \(#bind(exerciseID, as: UUID.self))
      """
    ).execute(database)
  }

  /// Builds and stores the completion from rows read inside the same write transaction.
  @discardableResult
  public static func complete(
    workoutKey: String,
    at completedAt: Date,
    completionID: UUID,
    healthWorkoutID: UUID? = nil,
    makeID: () -> UUID,
    in database: Database
  ) throws -> WorkoutCompletionSnapshot {
    let exerciseRows = try Exercise.all.fetchAll(database)
    let program = try CurrentProgramQuery.make(
      exerciseRows: exerciseRows,
      workoutRows: Workout.all.fetchAll(database),
      itemRows: WorkoutItem.all.fetchAll(database)
    )
    guard let workout = program.workouts.first(where: { $0.key == workoutKey }) else {
      throw Error.missingWorkout(workoutKey)
    }
    let snapshot = try CompletionSnapshots.make(
      workout: workout, exercises: program.exercises, completedAt: completedAt,
      completionID: completionID, makeID: makeID
    )
    let exerciseIDsByKey = Dictionary(uniqueKeysWithValues: CurrentProgramQuery
      .canonicalExerciseRows(exerciseRows)
      .filter { !$0.isRetired }
      .map { ($0.key, $0.id) })
    try save(snapshot, exerciseIDsByKey: exerciseIDsByKey, healthWorkoutID: healthWorkoutID, in: database)
    return snapshot
  }

  public static func undo(_ completionID: Completion.ID, in database: Database) throws {
    try Completion.find(completionID).delete().execute(database)
  }

  public static func correctDate(_ date: Date, completionID: Completion.ID, in database: Database) throws {
    try Completion.find(completionID).update { $0.completedAt = #bind(date) }.execute(database)
  }

  private static func save(
    _ snapshot: WorkoutCompletionSnapshot,
    exerciseIDsByKey: [String: Exercise.ID],
    healthWorkoutID: UUID?,
    in database: Database
  ) throws {
    let completion = Completion(
      id: snapshot.id, workoutKey: snapshot.workoutKey, completedAt: snapshot.completedAt,
      healthWorkoutID: healthWorkoutID
    )
    try Completion.insert { Completion.Draft(completion) }.execute(database)
    let rows = try snapshot.items.map { item -> CompletionItem.Draft in
      guard let exerciseID = exerciseIDsByKey[item.exerciseKey] else {
        throw Error.missingExerciseID(item.exerciseKey)
      }
      return CompletionItem.Draft(CompletionItem(
        id: item.id, completionID: snapshot.id, exerciseID: exerciseID,
        position: item.position, name: item.name, prescription: item.prescription,
        loadKind: item.load.kind, loadPounds: item.load.pounds
      ))
    }
    try CompletionItem.insert { rows }.execute(database)
  }
}

private extension Load {
  var kind: LoadKind {
    switch self {
    case .weight: .weight
    case .bodyweight: .bodyweight
    }
  }

  var pounds: Double? {
    guard case let .weight(pounds) = self else {
      return nil
    }
    return pounds
  }
}
