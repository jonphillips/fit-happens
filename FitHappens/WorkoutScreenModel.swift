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
  @ObservationIgnored @Dependency(\.healthClient) private var healthClient
  @ObservationIgnored @FetchAll(Exercise.all) private var exercises
  @ObservationIgnored @FetchAll(Workout.all) private var workouts
  @ObservationIgnored @FetchAll(WorkoutItem.all) private var workoutItems
  @ObservationIgnored @FetchAll(
    Completion.order { ($0.completedAt.desc(), $0.id.desc()) }.limit(20)
  ) private var completionHistory
  @ObservationIgnored @FetchAll(Completion.all) private var allCompletions

  var destination: Destination?
  var dateDraft = Date.now
  private(set) var healthWorkoutCandidate: HealthWorkout?
  private(set) var healthReadFailed = false

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

  func screenAppeared() async {
    let key = "FitHappensHealthReadAuthorizationRequested"
    if !UserDefaults.standard.bool(forKey: key) {
      UserDefaults.standard.set(true, forKey: key)
      do {
        try await healthClient.requestReadAuthorization()
      } catch {
        healthReadFailed = true
        return
      }
    }
    await refreshHealthWorkouts()
  }

  func acceptHealthWorkoutButtonTapped() {
    guard let candidate = healthWorkoutCandidate, let overview else {
      return
    }
    let result = withErrorReporting {
      try database.write { database in
        try WorkoutHistoryOperations.complete(
          workoutKey: overview.workoutKey,
          at: candidate.end,
          completionID: uuid(),
          healthWorkoutID: candidate.id,
          makeID: { uuid() },
          in: database
        )
      }
    }
    if result != nil {
      healthWorkoutCandidate = nil
    }
  }

  func declineHealthWorkoutButtonTapped() {
    guard let candidate = healthWorkoutCandidate else {
      return
    }
    var declined = declinedWorkoutEndDates()
    declined[candidate.id.uuidString] = candidate.end.timeIntervalSince1970
    UserDefaults.standard.set(declined, forKey: Self.declinedWorkoutsKey)
    healthWorkoutCandidate = nil
  }

  private func refreshHealthWorkouts() async {
    guard currentProgram != nil else {
      healthWorkoutCandidate = nil
      return
    }
    let currentDate = date.now
    let windowStart = currentDate.addingTimeInterval(-12 * 60 * 60)
    var declined = declinedWorkoutEndDates()
    declined = declined.filter { $0.value >= windowStart.timeIntervalSince1970 }
    UserDefaults.standard.set(declined, forKey: Self.declinedWorkoutsKey)
    do {
      let workouts = try await healthClient.strengthWorkouts(windowStart, currentDate)
      healthReadFailed = false
      healthWorkoutCandidate = StrengthWorkoutCandidate.pick(
        from: workouts,
        latestCompletionAt: latestCompletion?.completedAt,
        linkedWorkoutIDs: Set(allCompletions.compactMap(\.healthWorkoutID)),
        declinedWorkoutIDs: Set(declined.keys.compactMap(UUID.init(uuidString:))),
        now: currentDate
      )
    } catch {
      healthReadFailed = true
      healthWorkoutCandidate = nil
    }
  }

  private static let declinedWorkoutsKey = "FitHappensDeclinedHealthWorkouts"

  private func declinedWorkoutEndDates() -> [String: Double] {
    UserDefaults.standard.dictionary(forKey: Self.declinedWorkoutsKey) as? [String: Double] ?? [:]
  }

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
