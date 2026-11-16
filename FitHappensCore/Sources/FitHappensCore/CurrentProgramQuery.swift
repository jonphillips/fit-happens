import Foundation
import SQLiteData

public enum CurrentProgramQueryError: Error, Equatable, Sendable {
  case invalidLoad(String)
}

public enum CurrentProgramQuery {
  private struct ItemIdentity: Hashable {
    var workoutID: Workout.ID
    var exerciseID: Exercise.ID
  }

  /// Reads active exercises separately from retired keys, preventing old retirements
  /// from reappearing in each proposal while retaining enough data to restore a key.
  public static func fetch(in database: Database) throws -> CurrentProgram {
    try make(
      exerciseRows: Exercise.all.fetchAll(database),
      workoutRows: Workout.all.fetchAll(database),
      itemRows: WorkoutItem.all.fetchAll(database)
    )
  }

  /// Projects persisted rows into one canonical current program without writing to the database.
  public static func make(
    exerciseRows: [Exercise], workoutRows: [Workout], itemRows: [WorkoutItem]
  ) throws -> CurrentProgram {
    let exercisesByKey = Dictionary(uniqueKeysWithValues: canonicalExerciseRows(exerciseRows).map { ($0.key, $0) })
    let exercises = exercisesByKey.values.sorted { $0.key < $1.key }
    for exercise in exercises where !exercise.isRetired && exercise.load == nil {
      throw CurrentProgramQueryError.invalidLoad(exercise.key)
    }
    let exercisesByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
    let exerciseIDByRowID = Dictionary(uniqueKeysWithValues: exerciseRows.compactMap { row in
      exercisesByKey[row.key].map { (row.id, $0.id) }
    })

    let active = exercises.filter { !$0.isRetired }.map(currentExercise)
    let retired = exercises.filter(\.isRetired).map(currentExercise)
    let workouts = currentWorkouts(
      workoutRows: workoutRows,
      itemRows: itemRows,
      exercisesByID: exercisesByID,
      exerciseIDByRowID: exerciseIDByRowID
    )
    return CurrentProgram(exercises: active, retiredExercises: retired, workouts: workouts)
  }

  /// The canonical row for each exercise key, used by projections that also need its stable ID.
  public static func canonicalExerciseRows(_ rows: [Exercise]) -> [Exercise] {
    canonicalRows(rows, key: \.key, id: \.id).values.sorted { $0.key < $1.key }
  }

  private static func currentWorkouts(
    workoutRows: [Workout],
    itemRows: [WorkoutItem],
    exercisesByID: [Exercise.ID: Exercise],
    exerciseIDByRowID: [Exercise.ID: Exercise.ID]
  ) -> [CurrentWorkout] {
    let workoutsByKey = canonicalRows(workoutRows, key: \.key, id: \.id)
    let orderedWorkouts = workoutsByKey.values.sorted {
      if $0.position == $1.position {
        return $0.key < $1.key
      }
      return $0.position < $1.position
    }
    let workoutIDByRowID = Dictionary(uniqueKeysWithValues: workoutRows.compactMap { row in
      workoutsByKey[row.key].map { (row.id, $0.id) }
    })
    let items = selectedWorkoutItems(
      itemRows, workoutIDByRowID: workoutIDByRowID, exerciseIDByRowID: exerciseIDByRowID
    )
    let itemsByWorkout = Dictionary(grouping: items, by: \.workoutID)
    return orderedWorkouts.map { workout in
      let workoutItems = (itemsByWorkout[workout.id] ?? []).sorted {
        if $0.position == $1.position {
          return $0.id.uuidString < $1.id.uuidString
        }
        return $0.position < $1.position
      }
      let activeItems = workoutItems.compactMap { item -> (Exercise, WorkoutItem)? in
        guard let exercise = exercisesByID[item.exerciseID], !exercise.isRetired else {
          return nil
        }
        return (exercise, item)
      }
      return CurrentWorkout(
        key: workout.key,
        exerciseKeys: activeItems.map { $0.0.key },
        prescriptions: Dictionary(
          activeItems.map { ($0.0.key, $0.1.prescription) },
          uniquingKeysWith: { first, _ in first }
        )
      )
    }
  }

  private static func selectedWorkoutItems(
    _ rows: [WorkoutItem],
    workoutIDByRowID: [Workout.ID: Workout.ID],
    exerciseIDByRowID: [Exercise.ID: Exercise.ID]
  ) -> [WorkoutItem] {
    var selected: [ItemIdentity: WorkoutItem] = [:]
    for row in rows.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
      let workoutID = workoutIDByRowID[row.workoutID] ?? row.workoutID
      let exerciseID = exerciseIDByRowID[row.exerciseID] ?? row.exerciseID
      let identity = ItemIdentity(workoutID: workoutID, exerciseID: exerciseID)
      guard selected[identity] == nil else {
        continue
      }
      var canonical = row
      canonical.workoutID = workoutID
      canonical.exerciseID = exerciseID
      selected[identity] = canonical
    }
    return Array(selected.values)
  }

  private static func canonicalRows<Row, Key: Hashable>(
    _ rows: [Row], key: (Row) -> Key, id: (Row) -> UUID
  ) -> [Key: Row] {
    Dictionary(grouping: rows, by: key).compactMapValues { candidates in
      candidates.min { id($0).uuidString < id($1).uuidString }
    }
  }

  private static func currentExercise(_ record: Exercise) -> CurrentExercise {
    CurrentExercise(
      key: record.key, name: record.name, loadKind: record.loadKind, load: record.load,
      increment: record.increment, loadLabel: record.loadLabel, notes: record.notes
    )
  }
}
