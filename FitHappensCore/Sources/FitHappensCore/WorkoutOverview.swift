import Foundation
import SQLiteData

public struct WorkoutOverviewExercise: Equatable, Sendable, Identifiable {
  public var id: UUID
  public var key: String
  public var name: String
  public var prescription: String
  public var loadKind: LoadKind
  public var loadPounds: Double?
  public var increment: Double?
  public var loadLabel: String?

  public var load: Load? {
    guard loadKind == .weight, let loadPounds else {
      return nil
    }
    return .weight(pounds: loadPounds)
  }
}

public struct WorkoutOverview: Equatable, Sendable {
  public var workoutKey: String
  public var exercises: [WorkoutOverviewExercise]
  public var lastCompletedAt: Date?

  public static func make(
    workouts: [Workout], items: [WorkoutItem], exercises: [Exercise], completions: [Completion]
  ) -> WorkoutOverview? {
    let workoutWinnersByKey = Dictionary(grouping: workouts, by: \.key).compactMapValues { candidates in
      candidates.min { $0.id.uuidString < $1.id.uuidString }
    }
    let canonicalWorkouts = Array(workoutWinnersByKey.values)
      .sorted { $0.position == $1.position ? $0.key < $1.key : $0.position < $1.position }
    let exerciseWinnersByKey = Dictionary(grouping: exercises, by: \.key).compactMapValues { candidates in
      candidates.min { $0.id.uuidString < $1.id.uuidString }
    }
    let workoutByKey = Dictionary(uniqueKeysWithValues: canonicalWorkouts.map { ($0.key, $0) })
    let selectedWorkoutKey = WorkoutRotation.nextWorkoutKey(
      workoutKeys: canonicalWorkouts.map(\.key),
      completions: completions.map { CompletionSummary(workoutKey: $0.workoutKey, completedAt: $0.completedAt) }
    )
    guard let selectedWorkoutKey, let workout = workoutByKey[selectedWorkoutKey] else {
      return nil
    }
    let overviewExercises = exercisesForWorkout(
      workoutID: workout.id, workouts: workouts, workoutWinnersByKey: workoutWinnersByKey,
      items: items, exercises: exercises, exerciseWinnersByKey: exerciseWinnersByKey
    )
    let lastCompletedAt = completions.max {
      if $0.completedAt == $1.completedAt {
        return $0.id.uuidString < $1.id.uuidString
      }
      return $0.completedAt < $1.completedAt
    }?.completedAt
    return WorkoutOverview(workoutKey: workout.key, exercises: overviewExercises, lastCompletedAt: lastCompletedAt)
  }

  private static func exercisesForWorkout(
    workoutID: Workout.ID, workouts: [Workout], workoutWinnersByKey: [String: Workout],
    items: [WorkoutItem], exercises: [Exercise], exerciseWinnersByKey: [String: Exercise]
  ) -> [WorkoutOverviewExercise] {
    let canonicalWorkouts = Array(workoutWinnersByKey.values)
    let activeExercises = exerciseWinnersByKey.values.filter { !$0.isRetired }
    let exercisesByID = Dictionary(uniqueKeysWithValues: activeExercises.map { ($0.id, $0) })
    let workoutPairs: [(Workout.ID, Workout.ID)] = workouts.compactMap { row -> (Workout.ID, Workout.ID)? in
      workoutWinnersByKey[row.key].map { (row.id, $0.id) }
    }
    let workoutIDByRowID = Dictionary(uniqueKeysWithValues: workoutPairs)
    let exercisePairs: [(Exercise.ID, Exercise.ID)] = exercises.compactMap { row -> (Exercise.ID, Exercise.ID)? in
      guard let winner = exerciseWinnersByKey[row.key], !winner.isRetired else {
        return nil
      }
      return (row.id, winner.id)
    }
    let exerciseIDByRowID = Dictionary(uniqueKeysWithValues: exercisePairs)
    var selectedItems: [String: WorkoutItem] = [:]
    for item in items.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
      guard let workoutID = workoutIDByRowID[item.workoutID],
            let canonicalWorkout = canonicalWorkouts.first(where: { $0.id == workoutID }),
            let exerciseID = exerciseIDByRowID[item.exerciseID],
            let exercise = exercisesByID[exerciseID] else { continue }
      let key = "\(canonicalWorkout.key):\(exercise.key)"
      if selectedItems[key] == nil {
        var canonicalItem = item
        canonicalItem.workoutID = workoutID
        canonicalItem.exerciseID = exerciseID
        selectedItems[key] = canonicalItem
      }
    }
    let selectedValues = Array(selectedItems.values)
    let orderedItems = selectedValues.filter { $0.workoutID == workoutID }.sorted {
      $0.position == $1.position ? $0.id.uuidString < $1.id.uuidString : $0.position < $1.position
    }
    return orderedItems.compactMap { item -> WorkoutOverviewExercise? in
      guard let exercise = exercisesByID[item.exerciseID] else {
        return nil
      }
      return WorkoutOverviewExercise(
        id: exercise.id, key: exercise.key, name: exercise.name, prescription: item.prescription,
        loadKind: exercise.loadKind, loadPounds: exercise.currentLoadPounds,
        increment: exercise.increment, loadLabel: exercise.loadLabel
      )
    }
  }

}

public enum WorkoutHistoryOperations {
  public enum Error: Swift.Error {
    case missingExerciseID(String)
  }

  public static func setLoad(_ pounds: Double, exerciseID: Exercise.ID, in database: Database) throws {
    try Exercise.find(exerciseID).update { $0.currentLoadPounds = #bind(pounds) }.execute(database)
  }

  public static func save(
    _ snapshot: WorkoutCompletionSnapshot, exerciseIDsByKey: [String: Exercise.ID], in database: Database
  ) throws {
    let completion = Completion(
      id: snapshot.id, workoutKey: snapshot.workoutKey, completedAt: snapshot.completedAt
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

  public static func undo(_ completionID: Completion.ID, in database: Database) throws {
    try Completion.find(completionID).delete().execute(database)
  }

  public static func correctDate(_ date: Date, completionID: Completion.ID, in database: Database) throws {
    try Completion.find(completionID).update { $0.completedAt = #bind(date) }.execute(database)
  }

}

extension Load {
  fileprivate var kind: LoadKind {
    switch self {
    case .weight: .weight
    case .bodyweight: .bodyweight
    }
  }

  fileprivate var pounds: Double? {
    guard case let .weight(pounds) = self else {
      return nil
    }
    return pounds
  }
}
