import Foundation

public struct CompletionSummary: Equatable, Sendable {
  public var id: UUID
  public var workoutKey: String
  public var completedAt: Date

  public init(id: UUID, workoutKey: String, completedAt: Date) {
    self.id = id
    self.workoutKey = workoutKey
    self.completedAt = completedAt
  }

  /// A shared total order for rotation, history, and the latest-completion display.
  public static func isNewer(_ lhs: Self, than rhs: Self) -> Bool {
    if lhs.completedAt == rhs.completedAt {
      return lhs.id.uuidString > rhs.id.uuidString
    }
    return lhs.completedAt > rhs.completedAt
  }

  public static func latest(in completions: [Self]) -> Self? {
    completions.max { isNewer($1, than: $0) }
  }
}

public enum WorkoutRotation {
  public static func nextWorkoutKey(
    workoutKeys: [String], latestCompletion: CompletionSummary?
  ) -> String? {
    guard let first = workoutKeys.first else {
      return nil
    }
    guard let latestCompletion,
          let index = workoutKeys.firstIndex(of: latestCompletion.workoutKey) else {
      return first
    }
    return workoutKeys[(index + 1) % workoutKeys.count]
  }
}
