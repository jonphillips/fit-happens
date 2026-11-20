import Dependencies
import FitHappensCore
import Foundation
import SQLiteData
import UIKit

struct ClipboardClient: Sendable {
  var copy: @Sendable (String) -> Void
}

private enum ClipboardClientKey: DependencyKey {
  static let liveValue = ClipboardClient(copy: { text in
    Task { @MainActor in UIPasteboard.general.string = text }
  })
}

extension DependencyValues {
  var clipboardClient: ClipboardClient {
    get { self[ClipboardClientKey.self] }
    set { self[ClipboardClientKey.self] = newValue }
  }
}

struct ProgramReview: Equatable {
  var contractText: String
  var changeSet: ProgramChangeSet
  var proposedWorkouts: [ProgramWorkout]
  var warning: String?
  var isStoredRevision: Bool
}

enum ProgramImportRoute: Hashable {
  case review
}

@MainActor
@Observable
final class ProgramImportModel {
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.date) private var date
  @ObservationIgnored @Dependency(\.clipboardClient) private var clipboard
  @ObservationIgnored @FetchAll(Exercise.all) private var exercises
  @ObservationIgnored @FetchAll(Workout.all) private var workouts
  @ObservationIgnored @FetchAll(WorkoutItem.all) private var workoutItems
  @ObservationIgnored @FetchAll(
    Completion.order { ($0.completedAt.desc(), $0.id.desc()) }.limit(1)
  ) private var completions
  @ObservationIgnored @FetchAll(
    ProgramRevision.order { ($0.acceptedAt.desc(), $0.id.desc()) }
  ) private var revisions

  var path: [ProgramImportRoute] = []
  var programText = ""
  var review: ProgramReview?
  var errorMessage: String?
  var instructionsCopied = false
  var stagedURL: URL?

  var acceptedRevisions: [ProgramRevision] { revisions }
  var programOverview: ProgramOverview? {
    let program: CurrentProgram? = withErrorReporting {
      try CurrentProgramQuery.make(exerciseRows: exercises, workoutRows: workouts, itemRows: workoutItems)
    }
    guard let program else {
      return nil
    }
    let latest = completions.first.map {
      CompletionSummary(id: $0.id, workoutKey: $0.workoutKey, completedAt: $0.completedAt)
    }
    return ProgramOverview.make(program: program, latestCompletion: latest)
  }
  func reviewPastedProgram() {
    stagedURL = nil
    _ = makeReview(for: programText, isStoredRevision: false)
  }

  func reviewStagedProgram(_ text: String, url: URL) -> String? {
    stagedURL = url
    let error = makeReview(for: text, isStoredRevision: false)
    errorMessage = nil
    return error
  }

  func reviewRevision(_ revision: ProgramRevision) {
    stagedURL = nil
    programText = revision.contractText
    _ = makeReview(for: revision.contractText, isStoredRevision: true)
  }

  func applyReviewedProgram() -> Bool {
    guard let review else {
      return false
    }
    do {
      _ = try ProgramApplication.apply(
        programText: review.contractText, to: database, acceptedAt: date.now,
        isStoredRevision: review.isStoredRevision
      )
      errorMessage = nil
      return true
    } catch {
      errorMessage = ProgramErrorMessage.message(for: error)
      return false
    }
  }

  func copyInstructionsButtonTapped() {
    clipboard.copy(ProgramContractRules.instructions)
    instructionsCopied = true
  }

  private func makeReview(for text: String, isStoredRevision: Bool) -> String? {
    errorMessage = nil
    do {
      let decoded = try ProgramContractDecoder.decode(text)
      let current = try CurrentProgramQuery.make(
        exerciseRows: exercises, workoutRows: workouts, itemRows: workoutItems
      )
      let changes = try ProgramChanges.make(
        current: current, proposal: decoded.contract, isStoredRevision: isStoredRevision
      )
      review = ProgramReview(
        contractText: text,
        changeSet: changes,
        proposedWorkouts: decoded.contract.workouts,
        warning: decoded.warning,
        isStoredRevision: isStoredRevision
      )
      path.append(.review)
      return nil
    } catch {
      review = nil
      errorMessage = ProgramErrorMessage.message(for: error)
      return errorMessage
    }
  }

}
