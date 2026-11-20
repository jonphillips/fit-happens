import Dependencies
import FitHappensCore
import Foundation
import SQLiteData

@MainActor
@Observable
final class CompletionCorrectionsModel {
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.date) private var date
  @ObservationIgnored @FetchAll(
    Completion.order { ($0.completedAt.desc(), $0.id.desc()) }.limit(20)
  ) private var completions

  var dateDraft = Date.now
  var history: [Completion] { completions }
  var latestCompletion: Completion? { completions.first }
  var latestCompletionID: Completion.ID? { completions.first?.id }
  var now: Date { date.now }

  func changeDateButtonTapped(for completion: Completion) {
    dateDraft = completion.completedAt
  }

  @discardableResult
  func saveCorrectedDateButtonTapped(for completionID: Completion.ID) -> Bool {
    let result = withErrorReporting {
      try database.write { database in
        try WorkoutHistoryOperations.correctDate(dateDraft, completionID: completionID, in: database)
      }
      return true
    }
    return result ?? false
  }

  func undoCompletionButtonTapped(_ completionID: Completion.ID) {
    withErrorReporting {
      try database.write { database in
        try WorkoutHistoryOperations.undo(completionID, in: database)
      }
    }
  }
}
