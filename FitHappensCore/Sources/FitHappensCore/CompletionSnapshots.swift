import Foundation

public enum CompletionSnapshotError: Error, Equatable, Sendable {
  case missingExercise(String)
  case invalidLoad(String)
  case missingPrescription(String)
}

public struct CompletionExerciseSnapshot: Equatable, Sendable {
  public var id: UUID
  public var exerciseKey: String
  public var position: Int
  public var name: String
  public var prescription: String
  public var load: Load

  public init(
    id: UUID, exerciseKey: String, position: Int, name: String,
    prescription: String, load: Load
  ) {
    self.id = id
    self.exerciseKey = exerciseKey
    self.position = position
    self.name = name
    self.prescription = prescription
    self.load = load
  }
}

public struct WorkoutCompletionSnapshot: Equatable, Sendable {
  public var id: UUID
  public var workoutKey: String
  public var completedAt: Date
  public var items: [CompletionExerciseSnapshot]

  public init(id: UUID, workoutKey: String, completedAt: Date, items: [CompletionExerciseSnapshot]) {
    self.id = id
    self.workoutKey = workoutKey
    self.completedAt = completedAt
    self.items = items
  }
}

public enum CompletionSnapshots {
  public static func make(
    workout: CurrentWorkout, exercises: [CurrentExercise], completedAt: Date,
    completionID: UUID, makeID: () -> UUID
  ) throws -> WorkoutCompletionSnapshot {
    var exercisesByKey: [String: CurrentExercise] = [:]
    for exercise in exercises { exercisesByKey[exercise.key] = exercise }
    let items = try workout.exerciseKeys.enumerated().map { position, key -> CompletionExerciseSnapshot in
      guard let exercise = exercisesByKey[key] else {
        throw CompletionSnapshotError.missingExercise(key)
      }
      guard let load = exercise.load else { throw CompletionSnapshotError.invalidLoad(key) }
      guard let prescription = workout.prescriptions[key] else {
        throw CompletionSnapshotError.missingPrescription(key)
      }
      return CompletionExerciseSnapshot(
        id: makeID(), exerciseKey: key, position: position,
        name: exercise.name, prescription: prescription, load: load
      )
    }
    return WorkoutCompletionSnapshot(
      id: completionID, workoutKey: workout.key, completedAt: completedAt, items: items
    )
  }
}
