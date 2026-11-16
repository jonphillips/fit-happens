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
    ProgramRevision.order { ($0.acceptedAt.desc(), $0.id.desc()) }
  ) private var revisions

  var path: [ProgramImportRoute] = []
  var programText = ""
  var review: ProgramReview?
  var errorMessage: String?
  var instructionsCopied = false

  var acceptedRevisions: [ProgramRevision] { revisions }

  func reviewPastedProgram() {
    makeReview(for: programText)
  }

  func reviewRevision(_ revision: ProgramRevision) {
    programText = revision.contractText
    makeReview(for: revision.contractText)
  }

  func applyReviewedProgram() -> Bool {
    guard let review else {
      return false
    }
    do {
      _ = try ProgramApplication.apply(programText: review.contractText, to: database, acceptedAt: date.now)
      errorMessage = nil
      return true
    } catch {
      errorMessage = Self.message(for: error)
      return false
    }
  }

  func copyInstructionsButtonTapped() {
    clipboard.copy(ProgramContractRules.instructions)
    instructionsCopied = true
  }

  private func makeReview(for text: String) {
    errorMessage = nil
    do {
      let decoded = try ProgramContractDecoder.decode(text)
      let current = try CurrentProgramQuery.make(
        exerciseRows: exercises, workoutRows: workouts, itemRows: workoutItems
      )
      let changes = try ProgramChanges.make(current: current, proposal: decoded.contract)
      review = ProgramReview(
        contractText: text,
        changeSet: changes,
        proposedWorkouts: decoded.contract.workouts,
        warning: decoded.warning
      )
      path.append(.review)
    } catch {
      review = nil
      errorMessage = Self.message(for: error)
    }
  }

  private static func message(for error: Error) -> String {
    switch error {
    case let error as ProgramContractError:
      switch error {
      case let .unsupportedMarker(marker): "Unsupported program marker: \(marker)."
      case let .malformedJSON(path, reason): "Program data at \(path): \(reason)"
      case .emptyWorkouts: "Add at least one workout."
      case let .emptyWorkout(key): "Workout \(key) has no exercises."
      case .emptyWorkoutKey: "Every workout needs a key."
      case .emptyExerciseKey: "Every exercise needs a key."
      case let .emptyExerciseName(key): "Exercise \(key) needs a name."
      case let .emptyPrescription(key): "Exercise \(key) needs a prescription."
      case let .duplicateWorkoutKey(key): "Workout key \(key) appears more than once."
      case let .duplicateExerciseKey(workout, exercise):
        "Exercise key \(exercise) appears more than once in workout \(workout)."
      case let .conflictingExerciseDefinition(key): "Exercise \(key) has conflicting definitions."
      case let .missingStartingWeight(key): "New weighted exercise \(key) needs a startingWeight."
      case let .bodyweightHasStartingWeight(key): "Bodyweight exercise \(key) must omit startingWeight."
      case let .invalidWeight(key): "Exercise \(key) has an invalid weight."
      case let .invalidIncrement(key): "Exercise \(key) must have a positive increment."
      case let .loadKindChangedWithoutWeight(key):
        "Exercise \(key) needs a startingWeight when changing to weight."
      }
    case let error as CurrentProgramQueryError:
      switch error {
      case let .invalidLoad(key): "Saved exercise \(key) has an invalid working weight."
      }
    case let error as ProgramApplicationError:
      switch error {
      case let .duplicateExerciseKey(key): "Saved exercise key \(key) appears more than once."
      case let .duplicateWorkoutKey(key): "Saved workout key \(key) appears more than once."
      case let .duplicateWorkoutItem(workout, exercise):
        "Saved workout \(workout) has duplicate entries for \(exercise)."
      case let .invalidWeight(key): "Saved exercise \(key) has an invalid working weight."
      }
    default:
      "The program could not be reviewed. \(error.localizedDescription)"
    }
  }
}
