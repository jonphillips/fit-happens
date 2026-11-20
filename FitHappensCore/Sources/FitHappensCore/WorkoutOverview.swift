import Foundation

public struct WorkoutOverviewExercise: Equatable, Sendable, Identifiable {
  public var key: String
  public var name: String
  public var prescription: String
  public var loadKind: LoadKind
  public var loadPounds: Double?
  public var increment: Double?
  public var loadLabel: String?

  public var id: String { key }

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
    program: CurrentProgram, latestCompletion: CompletionSummary?
  ) -> WorkoutOverview? {
    guard let overview = ProgramOverview.make(program: program, latestCompletion: latestCompletion),
          let workout = overview.workouts.first(where: { $0.key == overview.nextWorkoutKey }) else {
      return nil
    }
    return WorkoutOverview(
      workoutKey: workout.key, exercises: workout.exercises, lastCompletedAt: latestCompletion?.completedAt
    )
  }
}

public struct ProgramOverview: Equatable, Sendable {
  public struct Workout: Equatable, Sendable, Identifiable {
    public var key: String
    public var exercises: [WorkoutOverviewExercise]
    public var id: String { key }
  }

  public var workouts: [Workout]
  public var nextWorkoutKey: String

  public static func make(program: CurrentProgram, latestCompletion: CompletionSummary?) -> Self? {
    guard let nextWorkoutKey = WorkoutRotation.nextWorkoutKey(
      workoutKeys: program.workouts.map(\.key), latestCompletion: latestCompletion
    ) else { return nil }

    let exercisesByKey = Dictionary(uniqueKeysWithValues: program.exercises.map { ($0.key, $0) })
    let workouts = program.workouts.map { workout in
      Workout(
        key: workout.key,
        exercises: workout.exerciseKeys.compactMap { key in
          guard let exercise = exercisesByKey[key], let prescription = workout.prescriptions[key] else {
            return nil
          }
          return WorkoutOverviewExercise(
            key: exercise.key, name: exercise.name, prescription: prescription,
            loadKind: exercise.loadKind, loadPounds: exercise.load?.pounds,
            increment: exercise.increment, loadLabel: exercise.loadLabel
          )
        }
      )
    }
    return Self(workouts: workouts, nextWorkoutKey: nextWorkoutKey)
  }
}

private extension Load {
  var pounds: Double? {
    guard case let .weight(pounds) = self else {
      return nil
    }
    return pounds
  }
}
