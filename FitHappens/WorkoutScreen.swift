import FitHappensCore
import SwiftUI

struct WorkoutScreen: View {
  @State private var model = WorkoutScreenModel()
  @State private var showingLastDone = false
  @Environment(CompletionCorrectionsModel.self) private var correctionsModel
  @Binding var selectedTab: AppTab
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    NavigationStack {
      mainContent
        .navigationTitle("Next Workout")
        .sheet(isPresented: $showingLastDone) {
          LatestCompletionCorrectionScreen(model: correctionsModel)
        }
        .task(id: scenePhase) {
          guard scenePhase == .active else {
            return
          }
          await model.screenAppeared()
        }
    }
  }

  @ViewBuilder
  private var mainContent: some View {
    if let overview = model.overview {
      workout(overview)
    } else {
      VStack(spacing: 12) {
        ContentUnavailableView(
          "No program yet",
          systemImage: "dumbbell",
          description: Text("Import a workout program to get started.")
        )
        Button("Import Program", systemImage: "doc.text") { selectedTab = .program }
          .buttonStyle(.borderedProminent)
      }
    }
  }

  private func workout(_ overview: WorkoutOverview) -> some View {
    List {
      WorkoutSummaryRow(overview: overview) { showingLastDone = true }

      if let candidate = model.healthWorkoutCandidate {
        HealthWorkoutOffer(
          workout: candidate,
          nextWorkoutKey: overview.workoutKey,
          accept: model.acceptHealthWorkoutButtonTapped,
          decline: model.declineHealthWorkoutButtonTapped
        )
      } else if model.healthReadFailed {
        Section {
          Text("Health data couldn’t be loaded.")
            .foregroundStyle(.secondary)
        }
      }

      Section("Exercises") {
        ForEach(Array(overview.exercises.enumerated()), id: \.element.id) { index, exercise in
          ExerciseRow(
            index: index + 1,
            exercise: exercise,
            decrement: { model.loadStepperChanged(exercise, by: -1) },
            increment: { model.loadStepperChanged(exercise, by: 1) }
          )
        }
      }

      CompleteWorkoutRow(action: model.completeWorkoutButtonTapped)
    }
  }
}

private struct HealthWorkoutOffer: View {
  var workout: HealthWorkout
  var nextWorkoutKey: String
  var accept: () -> Void
  var decline: () -> Void

  private var durationMinutes: Int {
    Int((workout.end.timeIntervalSince(workout.start) / 60).rounded())
  }

  private var startTime: String {
    workout.start.formatted(date: .omitted, time: .shortened)
  }

  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 12) {
        Text("\(durationMinutes)-minute strength workout at \(startTime) — mark Workout \(nextWorkoutKey) done?")
          .font(.headline)
        HStack {
          Button("Mark done", systemImage: "checkmark.circle.fill", action: accept)
            .buttonStyle(.borderedProminent)
          Button("Not this one", action: decline)
            .buttonStyle(.bordered)
        }
      }
      .padding(.vertical, 4)
    } header: {
      Text("Watch Workout")
    }
  }
}

private struct WorkoutSummaryRow: View {
  var overview: WorkoutOverview
  var lastDoneTapped: () -> Void

  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 6) {
        Text("Workout \(overview.workoutKey)")
          .font(.largeTitle.bold())
        if let lastCompletedAt = overview.lastCompletedAt {
          Button(action: lastDoneTapped) {
            Text("Last done \(lastCompletedAt, format: .dateTime.month().day().year())")
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        } else {
          Text("No workouts completed yet")
            .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, 8)
    }
  }
}

private struct CompleteWorkoutRow: View {
  var action: () -> Void

  var body: some View {
    Section {
      Button("Complete Workout", systemImage: "checkmark.circle.fill", action: action)
        .font(.headline)
        .frame(maxWidth: .infinity, alignment: .center)
    }
  }
}

private struct ExerciseRow: View {
  var index: Int
  var exercise: WorkoutOverviewExercise
  var decrement: () -> Void
  var increment: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("\(index). \(exercise.name)")
          .font(.headline)
        Spacer(minLength: 8)
        Text(exercise.prescription)
          .foregroundStyle(.secondary)
      }
      if exercise.loadKind == .weight {
        WeightControl(exercise: exercise, decrement: decrement, increment: increment)
      } else {
        Text("Bodyweight")
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 6)
  }
}

private struct WeightControl: View {
  var exercise: WorkoutOverviewExercise
  var decrement: () -> Void
  var increment: () -> Void

  var body: some View {
    if let load = exercise.loadPounds {
      HStack {
        Text(load, format: .number.precision(.fractionLength(0...2)))
          .font(.title3.monospacedDigit())
        Text("lb\(exercise.loadLabel.map { " \($0)" } ?? "")")
          .foregroundStyle(.secondary)
        Spacer()
        Button(action: decrement) {
          Label("Decrease weight", systemImage: "minus.circle")
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
          .buttonStyle(.borderless)
          .disabled(load <= 0)
        Button(action: increment) {
          Label("Increase weight", systemImage: "plus.circle")
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
          .buttonStyle(.borderless)
      }
      .accessibilityElement(children: .contain)
    } else {
      Text("Weight not set")
        .foregroundStyle(.secondary)
    }
  }
}
