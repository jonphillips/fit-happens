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
  @ObservationIgnored @FetchAll(Completion.all) private var completions

  var destination: Destination?
  var dateDraft = Date.now

  enum Destination: Identifiable {
    case history
    case correctDate(Completion.ID)

    var id: String {
      switch self {
      case .history: "history"
      case let .correctDate(id): id.uuidString
      }
    }
  }

  var overview: WorkoutOverview? {
    WorkoutOverview.make(workouts: workouts, items: workoutItems, exercises: exercises, completions: completions)
  }

  var history: [Completion] {
    completions.sorted {
      if $0.completedAt == $1.completedAt {
        return $0.id.uuidString > $1.id.uuidString
      }
      return $0.completedAt > $1.completedAt
    }
  }

  var latestCompletionID: Completion.ID? { history.first?.id }

  func loadStepperChanged(_ exercise: WorkoutOverviewExercise, by direction: Double) {
    guard let load = exercise.loadPounds, let increment = exercise.increment else {
      return
    }
    let updatedLoad = max(0, load + increment * direction)
    withErrorReporting {
      try database.write { database in
        try WorkoutHistoryOperations.setLoad(updatedLoad, exerciseID: exercise.id, in: database)
      }
    }
  }

  func completeWorkoutButtonTapped() {
    guard let overview else {
      return
    }
    let currentExercises = canonicalActiveExercises
    let domainExercises = currentExercises.values.map { exercise in
      CurrentExercise(
        key: exercise.key, name: exercise.name, loadKind: exercise.loadKind, load: exercise.load,
        increment: exercise.increment, loadLabel: exercise.loadLabel, notes: exercise.notes
      )
    }
    let domainWorkout = CurrentWorkout(
      key: overview.workoutKey,
      exerciseKeys: overview.exercises.map(\.key),
      prescriptions: Dictionary(uniqueKeysWithValues: overview.exercises.map { ($0.key, $0.prescription) })
    )
    withErrorReporting {
      let snapshot = try CompletionSnapshots.make(
        workout: domainWorkout, exercises: domainExercises, completedAt: date.now,
        completionID: uuid(), makeID: { uuid() }
      )
      let exerciseIDsByKey = Dictionary(uniqueKeysWithValues: currentExercises.map { ($0.key, $0.value.id) })
      try database.write { database in
        try WorkoutHistoryOperations.save(snapshot, exerciseIDsByKey: exerciseIDsByKey, in: database)
      }
    }
  }

  func historyButtonTapped() {
    destination = .history
  }

  private var canonicalActiveExercises: [String: Exercise] {
    exercises.filter { !$0.isRetired }.reduce(into: [String: Exercise]()) { result, exercise in
      guard let existing = result[exercise.key] else {
        result[exercise.key] = exercise
        return
      }
      if exercise.id.uuidString < existing.id.uuidString {
        result[exercise.key] = exercise
      }
    }
  }

  func changeDateButtonTapped(for completion: Completion) {
    dateDraft = completion.completedAt
    destination = .correctDate(completion.id)
  }

  func saveCorrectedDateButtonTapped(for completionID: Completion.ID) {
    withErrorReporting {
      try database.write { database in
        try WorkoutHistoryOperations.correctDate(dateDraft, completionID: completionID, in: database)
      }
    }
    destination = nil
  }

  func undoLatestButtonTapped() {
    guard let id = latestCompletionID else {
      return
    }
    withErrorReporting {
      try database.write { database in try WorkoutHistoryOperations.undo(id, in: database) }
    }
  }
}
