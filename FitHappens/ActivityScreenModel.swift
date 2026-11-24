import Dependencies
import FitHappensCore
import Foundation
import Sharing
import SQLiteData

@MainActor
@Observable
final class ActivityScreenModel {
  @ObservationIgnored @Dependency(\.date) private var date
  @ObservationIgnored @Dependency(\.healthClient) private var healthClient
  @ObservationIgnored @FetchAll(Exercise.all) private var exercises
  @ObservationIgnored @FetchAll(Workout.all) private var workouts
  @ObservationIgnored @FetchAll(WorkoutItem.all) private var workoutItems
  @ObservationIgnored @FetchAll(Completion.all) private var completions
  @ObservationIgnored @FetchAll(CompletionItem.all) private var completionItems
  @ObservationIgnored @Shared(.appStorage("fitHappensActivityExerciseKey"))
  var selectedExerciseKey: String? = nil

  private(set) var strengthWorkouts: [HealthWorkout] = []
  private(set) var walkingWorkouts: [HealthWalkingWorkout] = []
  private(set) var latestBodyMass: HealthBodyMass?
  private(set) var healthReadAccess: HealthReadAccess?
  private(set) var hasLoaded = false
  var hasHealthActivity: Bool { !strengthWorkouts.isEmpty || !walkingWorkouts.isEmpty }

  var currentProgram: CurrentProgram? {
    withErrorReporting {
      try CurrentProgramQuery.make(exerciseRows: exercises, workoutRows: workouts, itemRows: workoutItems)
    }
  }

  var orderedWeightedExercises: [Exercise] {
    guard let currentProgram else {
      return []
    }
    return ActivityProjection.orderedWeightedExercises(program: currentProgram, exercises: exercises)
  }

  var selectedExercise: Exercise? {
    guard let selectedExerciseKey else {
      return nil
    }
    return orderedWeightedExercises.first { $0.key == selectedExerciseKey }
  }

  func calendarDays(calendar: Calendar) -> [ActivityDay] {
    ActivityProjection.calendarDays(
      now: date.now, calendar: calendar, completions: completions,
      strengthWorkouts: strengthWorkouts, walkingWorkouts: walkingWorkouts
    )
  }

  func progression(calendar: Calendar) -> ExerciseProgression? {
    ActivityProjection.progression(
      exercise: selectedExercise, exercises: exercises, completions: completions, items: completionItems,
      now: date.now, calendar: calendar
    )
  }

  func screenAppeared(calendar: Calendar) async {
    await loadHealth(calendar: calendar)
  }

  func connectToHealthButtonTapped(calendar: Calendar) async {
    await loadHealth(calendar: calendar)
  }

  private func loadHealth(calendar: Calendar) async {
    if let currentProgram,
       selectedExerciseKey.map({ key in orderedWeightedExercises.contains(where: { $0.key == key }) }) != true {
      let defaultKey = ActivityProjection.defaultExercise(program: currentProgram, exercises: exercises)?.key
      $selectedExerciseKey.withLock { $0 = defaultKey }
    }

    let now = date.now
    guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now),
          let start = calendar.date(byAdding: .weekOfYear, value: -3, to: currentWeek.start)
    else {
      hasLoaded = true
      return
    }
    do {
      let access = try await healthClient.requestReadAuthorization()
      healthReadAccess = access
      guard access == .ready else {
        clearHealthData()
        hasLoaded = true
        return
      }
      async let strength = healthClient.strengthWorkouts(start, date.now)
      async let walking = healthClient.walkingWorkouts(start, date.now)
      async let bodyMass = healthClient.latestBodyMass()
      strengthWorkouts = try await strength
      walkingWorkouts = try await walking
      latestBodyMass = try await bodyMass
    } catch is CancellationError {
      return
    } catch {
      clearHealthData()
      healthReadAccess = .failed(error.localizedDescription)
    }
    hasLoaded = true
  }

  private func clearHealthData() {
    strengthWorkouts = []
    walkingWorkouts = []
    latestBodyMass = nil
  }
}
