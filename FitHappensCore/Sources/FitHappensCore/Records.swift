import Foundation
import SQLiteData

public enum LoadKind: String, Codable, Equatable, QueryBindable, Sendable {
  case weight
  case bodyweight
}

public enum Load: Equatable, Sendable {
  case weight(pounds: Double)
  case bodyweight
}

@Table
public struct Exercise: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var key: String
  public var name: String
  public var loadKind: LoadKind
  public var currentLoadPounds: Double?
  public var increment: Double?
  public var loadLabel: String?
  public var notes: String?
  public var isRetired: Bool

  public init(
    id: UUID, key: String, name: String, loadKind: LoadKind,
    currentLoadPounds: Double? = nil, increment: Double? = nil,
    loadLabel: String? = nil, notes: String? = nil, isRetired: Bool = false
  ) {
    self.id = id
    self.key = key
    self.name = name
    self.loadKind = loadKind
    self.currentLoadPounds = loadKind == .weight ? currentLoadPounds : nil
    self.increment = increment
    self.loadLabel = loadLabel
    self.notes = notes
    self.isRetired = isRetired
  }

  public var load: Load? {
    switch (loadKind, currentLoadPounds) {
    case let (.weight, .some(pounds)): .weight(pounds: pounds)
    case (.bodyweight, .none): .bodyweight
    default: nil
    }
  }
}

@Table
public struct Workout: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var key: String
  public var position: Int

  public init(id: UUID, key: String, position: Int) {
    self.id = id
    self.key = key
    self.position = position
  }
}

@Table
public struct WorkoutItem: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var workoutID: Workout.ID
  public var exerciseID: Exercise.ID
  public var position: Int
  public var prescription: String
  public var ramp: String?

  public init(
    id: UUID, workoutID: Workout.ID, exerciseID: Exercise.ID, position: Int,
    prescription: String, ramp: String? = nil
  ) {
    self.id = id
    self.workoutID = workoutID
    self.exerciseID = exerciseID
    self.position = position
    self.prescription = prescription
    self.ramp = ramp
  }
}

@Table
public struct ProgramRevision: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var acceptedAt: Date
  public var contractText: String

  public init(id: UUID, acceptedAt: Date, contractText: String) {
    self.id = id
    self.acceptedAt = acceptedAt
    self.contractText = contractText
  }
}

@Table
public struct Completion: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var workoutKey: String
  public var completedAt: Date
  public var healthWorkoutID: UUID?

  public init(id: UUID, workoutKey: String, completedAt: Date, healthWorkoutID: UUID? = nil) {
    self.id = id
    self.workoutKey = workoutKey
    self.completedAt = completedAt
    self.healthWorkoutID = healthWorkoutID
  }
}

@Table
public struct CompletionItem: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var completionID: Completion.ID
  public var exerciseID: Exercise.ID
  public var position: Int
  public var name: String
  public var prescription: String
  public var loadKind: LoadKind
  public var loadPounds: Double?

  public init(
    id: UUID, completionID: Completion.ID, exerciseID: Exercise.ID, position: Int,
    name: String, prescription: String, loadKind: LoadKind, loadPounds: Double?
  ) {
    self.id = id
    self.completionID = completionID
    self.exerciseID = exerciseID
    self.position = position
    self.name = name
    self.prescription = prescription
    self.loadKind = loadKind
    self.loadPounds = loadKind == .weight ? loadPounds : nil
  }
}
