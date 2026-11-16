import Foundation

public struct CompletionSummary: Equatable, Sendable {
  public var workoutKey: String
  public var completedAt: Date

  public init(workoutKey: String, completedAt: Date) {
    self.workoutKey = workoutKey
    self.completedAt = completedAt
  }
}

public enum WorkoutRotation {
  public static func nextWorkoutKey(
    workoutKeys: [String], completions: [CompletionSummary]
  ) -> String? {
    guard let first = workoutKeys.first else {
      return nil
    }
    guard let latest = completions.max(by: { $0.completedAt < $1.completedAt }),
          let index = workoutKeys.firstIndex(of: latest.workoutKey)
    else {
      return first
    }
    return workoutKeys[(index + 1) % workoutKeys.count]
  }
}
