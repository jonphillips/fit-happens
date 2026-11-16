import Dependencies
import FitHappensCore
import Foundation
import SQLiteData
import SwiftUI

@MainActor
@Observable
final class WorkoutScreenModel {
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.date) private var date
  @ObservationIgnored @Dependency(\.uuid) private var uuid
  @ObservationIgnored @FetchAll(Exercise.all) private var exercises
  @ObservationIgnored @FetchAll(Workout.all) private var workouts
  @ObservationIgnored @FetchAll(WorkoutItem.all) private var workoutItems
  @ObservationIgnored @FetchAll(
    Completion.order { ($0.completedAt.desc(), $0.id.desc()) }.limit(20)
  ) private var completionHistory

  var destination: Destination?
  var dateDraft = Date.now

  enum Destination: Identifiable {
    case history
    case programImport

    var id: String {
      switch self {
      case .history: "history"
      case .programImport: "programImport"
      }
    }
  }

  var currentProgram: CurrentProgram? {
    withErrorReporting {
      try CurrentProgramQuery.make(exerciseRows: exercises, workoutRows: workouts, itemRows: workoutItems)
    }
  }

  var overview: WorkoutOverview? {
    guard let currentProgram else {
      return nil
    }
    return WorkoutOverview.make(program: currentProgram, latestCompletion: latestCompletion)
  }

  var latestCompletion: CompletionSummary? {
    completionHistory.first.map {
      CompletionSummary(id: $0.id, workoutKey: $0.workoutKey, completedAt: $0.completedAt)
    }
  }

  var history: [Completion] { completionHistory }
  var latestCompletionID: Completion.ID? { completionHistory.first?.id }
  var now: Date { date.now }

  func loadStepperChanged(_ exercise: WorkoutOverviewExercise, by direction: Int) {
    guard let row = CurrentProgramQuery.canonicalExerciseRows(exercises).first(where: { $0.key == exercise.key }) else {
      return
    }
    withErrorReporting {
      try database.write { database in
        try WorkoutHistoryOperations.stepLoad(
          exerciseID: row.id, direction: direction, configuredIncrement: exercise.increment, in: database
        )
      }
    }
  }

  func completeWorkoutButtonTapped() {
    guard let overview else {
      return
    }
    _ = withErrorReporting {
      try database.write { database in
        try WorkoutHistoryOperations.complete(
          workoutKey: overview.workoutKey, at: date.now, completionID: uuid(), makeID: { uuid() }, in: database
        )
      }
    }
  }

  func historyButtonTapped() {
    destination = .history
  }

  func programButtonTapped() {
    destination = .programImport
  }

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
