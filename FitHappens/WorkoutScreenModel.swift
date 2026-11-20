import Dependencies
import FitHappensCore
import Foundation
import Sharing
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
  @ObservationIgnored @Shared(.appStorage("fitHappensHealthAuthRequested"))
  private var healthAuthorizationRequested = false
  @ObservationIgnored @Shared(.appStorage("fitHappensDeclinedHealthWorkouts"))
  private var declinedWorkoutEndDatesRaw = ""

  private(set) var recentStrengthWorkouts: [HealthWorkout] = []
  private(set) var healthReadFailed = false

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

  var healthWorkoutCandidate: HealthWorkout? {
    StrengthWorkoutCandidate.pick(
      from: recentStrengthWorkouts,
      latestCompletionAt: latestCompletion?.completedAt,
      linkedWorkoutIDs: Set(allCompletions.compactMap(\.healthWorkoutID)),
      declinedWorkoutIDs: Set(declinedWorkoutEndDates.keys),
      now: date.now
    )
  }

  func screenAppeared() async {
    if !healthAuthorizationRequested {
      do {
        try await healthClient.requestReadAuthorization()
        $healthAuthorizationRequested.withLock { $0 = true }
      } catch is CancellationError {
        return
      } catch {
        $healthAuthorizationRequested.withLock { $0 = true }
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
    _ = withErrorReporting {
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
  }

  func declineHealthWorkoutButtonTapped() {
    guard let candidate = healthWorkoutCandidate else {
      return
    }
    var declined = declinedWorkoutEndDates
    declined[candidate.id] = candidate.end
    let serializedDeclined = declined
      .sorted { $0.key.uuidString < $1.key.uuidString }
      .map { "\($0.key.uuidString):\($0.value.timeIntervalSince1970)" }
      .joined(separator: ",")
    $declinedWorkoutEndDatesRaw.withLock { $0 = serializedDeclined }
  }

  private func refreshHealthWorkouts() async {
    guard currentProgram != nil else {
      recentStrengthWorkouts = []
      return
    }
    let currentDate = date.now
    let windowStart = currentDate.addingTimeInterval(-12 * 60 * 60)
    do {
      let workouts = try await healthClient.strengthWorkouts(windowStart, currentDate)
      recentStrengthWorkouts = workouts
      pruneDeclinedWorkoutIDs(olderThan: windowStart)
      healthReadFailed = false
    } catch is CancellationError {
      return
    } catch {
      healthReadFailed = true
    }
  }

  private var declinedWorkoutEndDates: [UUID: Date] {
    Dictionary(uniqueKeysWithValues: declinedWorkoutEndDatesRaw.split(separator: ",").compactMap { entry in
      let fields = entry.split(separator: ":", maxSplits: 1)
      guard fields.count == 2,
            let id = UUID(uuidString: String(fields[0])),
            let endTimestamp = Double(fields[1])
      else {
        return nil
      }
      return (id, Date(timeIntervalSince1970: endTimestamp))
    })
  }

  private func pruneDeclinedWorkoutIDs(olderThan cutoff: Date) {
    let retained = declinedWorkoutEndDates.filter { $0.value >= cutoff }
    let serializedRetained = retained
      .sorted { $0.key.uuidString < $1.key.uuidString }
      .map { "\($0.key.uuidString):\($0.value.timeIntervalSince1970)" }
      .joined(separator: ",")
    $declinedWorkoutEndDatesRaw.withLock { $0 = serializedRetained }
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

}
