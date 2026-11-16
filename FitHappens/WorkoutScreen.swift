import FitHappensCore
import SwiftUI

struct WorkoutScreen: View {
  @State private var model = WorkoutScreenModel()

  var body: some View {
    NavigationStack {
      Group {
        if let overview = model.overview {
          workout(overview)
        } else {
          ContentUnavailableView(
            "No program yet",
            systemImage: "dumbbell",
            description: Text("Import a workout program to get started.")
          )
        }
      }
      .navigationTitle("Next Workout")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("History", systemImage: "clock") { model.historyButtonTapped() }
        }
      }
      .sheet(item: $model.destination) { destination in
        WorkoutDestinationSheet(destination: destination, model: model)
      }
    }
  }

  private func workout(_ overview: WorkoutOverview) -> some View {
    List {
      WorkoutSummaryRow(overview: overview)

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

private struct WorkoutDestinationSheet: View {
  var destination: WorkoutScreenModel.Destination
  var model: WorkoutScreenModel

  @ViewBuilder
  var body: some View {
    switch destination {
    case .history:
      HistoryScreen(model: model)
    case let .correctDate(id):
      DateCorrectionScreen(model: model, completionID: id)
    }
  }
}

private struct WorkoutSummaryRow: View {
  var overview: WorkoutOverview

  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 6) {
        Text("Workout \(overview.workoutKey)")
          .font(.largeTitle.bold())
        if let lastCompletedAt = overview.lastCompletedAt {
          Text("Last done \(lastCompletedAt, format: .dateTime.month().day().year())")
            .foregroundStyle(.secondary)
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
        Button("Decrease weight", systemImage: "minus.circle", action: decrement)
          .labelStyle(.iconOnly)
          .disabled(exercise.increment == nil || load <= 0)
        Button("Increase weight", systemImage: "plus.circle", action: increment)
          .labelStyle(.iconOnly)
          .disabled(exercise.increment == nil)
      }
      .accessibilityElement(children: .contain)
    } else {
      Text("Weight not set")
        .foregroundStyle(.secondary)
    }
  }
}

private struct HistoryScreen: View {
  var model: WorkoutScreenModel

  var body: some View {
    NavigationStack {
      HistoryList(model: model)
      .navigationTitle("History")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { model.destination = nil }
        }
      }
    }
  }
}

private struct HistoryList: View {
  var model: WorkoutScreenModel

  var body: some View {
    List {
      if model.history.isEmpty {
        ContentUnavailableView("No workouts yet", systemImage: "clock")
      } else {
        ForEach(model.history) { completion in
          HistoryRow(
            completion: completion,
            isLatest: completion.id == model.latestCompletionID,
            changeDate: { model.changeDateButtonTapped(for: completion) },
            undo: model.undoLatestButtonTapped
          )
        }
      }
    }
  }
}

private struct HistoryRow: View {
  var completion: Completion
  var isLatest: Bool
  var changeDate: () -> Void
  var undo: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Workout \(completion.workoutKey)")
          .font(.headline)
        Spacer()
        Text(completion.completedAt, format: .dateTime.month().day().year())
          .foregroundStyle(.secondary)
      }
      Button("Change date", action: changeDate)
        .font(.subheadline)
      if isLatest {
        Button("Undo this completion", role: .destructive, action: undo)
          .font(.subheadline)
      }
    }
    .padding(.vertical, 4)
  }
}

private struct DateCorrectionScreen: View {
  @Bindable var model: WorkoutScreenModel
  var completionID: Completion.ID

  var body: some View {
    NavigationStack {
      Form {
        DatePicker("Completed", selection: $model.dateDraft, displayedComponents: .date)
      }
      .navigationTitle("Change Date")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { model.destination = .history }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { model.saveCorrectedDateButtonTapped(for: completionID) }
        }
      }
    }
  }
}
