import SQLiteData

public enum CurrentProgramQueryError: Error, Equatable, Sendable {
  case invalidLoad(String)
}

public enum CurrentProgramQuery {
  /// Reads active exercises separately from retired keys, preventing old retirements
  /// from reappearing in each proposal while retaining enough data to restore a key.
  public static func fetch(in database: Database) throws -> CurrentProgram {
    let records = try Exercise.all.fetchAll(database)
    for exercise in records where exercise.load == nil {
      throw CurrentProgramQueryError.invalidLoad(exercise.key)
    }
    let exercisesByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    let orderedWorkouts = try Workout.all.fetchAll(database).sorted {
      if $0.position == $1.position {
        return $0.key < $1.key
      }
      return $0.position < $1.position
    }
    let orderedItems = try WorkoutItem.all.fetchAll(database).sorted {
      if $0.workoutID == $1.workoutID, $0.position == $1.position {
        return $0.id.uuidString < $1.id.uuidString
      }
      if $0.workoutID == $1.workoutID {
        return $0.position < $1.position
      }
      return $0.workoutID.uuidString < $1.workoutID.uuidString
    }
    let active = records.filter { !$0.isRetired }.map(currentExercise)
    let retired = records.filter(\.isRetired).map(currentExercise)
    let workouts = orderedWorkouts.map { workout in
      let items = orderedItems.filter { $0.workoutID == workout.id }
      let activeItems = items.compactMap { item -> (Exercise, WorkoutItem)? in
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
    return CurrentProgram(exercises: active, retiredExercises: retired, workouts: workouts)
  }

  private static func currentExercise(_ record: Exercise) -> CurrentExercise {
    CurrentExercise(
      key: record.key, name: record.name, loadKind: record.loadKind, load: record.load,
      increment: record.increment, loadLabel: record.loadLabel, notes: record.notes
    )
  }
}
