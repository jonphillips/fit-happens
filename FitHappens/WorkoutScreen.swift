import FitHappensCore
import FitHappensInboxKit
import SwiftUI

struct WorkoutScreen: View {
  @State private var model = WorkoutScreenModel()
  @State private var chatAccessModel = ChatAccessExportModel()
  @Environment(\.scenePhase) private var scenePhase
  @Environment(ChatInboxModel.self) private var chatInbox

  var body: some View {
    NavigationStack {
      mainContent
        .navigationTitle("Next Workout")
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            programButton
          }
          ToolbarItem(placement: .topBarTrailing) {
            Button("History", systemImage: "clock") { model.historyButtonTapped() }
          }
        }
        .sheet(item: $model.destination) { destination in
          presentedScreen(for: destination)
        }
        .task(id: scenePhase) {
          guard scenePhase == .active else {
            return
          }
          await model.screenAppeared()
        }
        .onChange(of: scenePhase) { _, phase in
          guard phase == .background else {
            return
          }
          chatAccessModel.appDidEnterBackground()
        }
    }
  }

  private var programButton: some View {
    Button {
      model.programButtonTapped()
    } label: {
      HStack(spacing: 6) {
        Label("Program", systemImage: "doc.text")
        if chatInbox.readyCount > 0 {
          Text(chatInbox.readyCount.formatted())
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
        }
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
        Button("Import Program", systemImage: "doc.text") { model.programButtonTapped() }
          .buttonStyle(.borderedProminent)
      }
    }
  }

  @ViewBuilder
  private func presentedScreen(for destination: WorkoutScreenModel.Destination) -> some View {
    switch destination {
    case .history: HistoryScreen(model: model)
    case .programImport: ProgramImportScreen(exportModel: chatAccessModel)
    }
  }

  private func workout(_ overview: WorkoutOverview) -> some View {
    List {
      WorkoutSummaryRow(overview: overview)

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

private struct HistoryScreen: View {
  var model: WorkoutScreenModel
  @State private var path: [Completion.ID] = []

  var body: some View {
    NavigationStack(path: $path) {
      HistoryList(model: model, openDateCorrection: { path.append($0) })
        .navigationTitle("History")
        .navigationDestination(for: Completion.ID.self) { completionID in
          DateCorrectionScreen(model: model, completionID: completionID)
        }
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
  @State private var completionToUndo: Completion? = nil
  var openDateCorrection: (Completion.ID) -> Void = { _ in }

  var body: some View {
    List {
      if model.history.isEmpty {
        ContentUnavailableView("No workouts yet", systemImage: "clock")
      } else {
        let latestCompletionID = model.latestCompletionID
        ForEach(model.history) { completion in
          HistoryRow(
            completion: completion,
            isLatest: completion.id == latestCompletionID,
            changeDate: {
              model.changeDateButtonTapped(for: completion)
              openDateCorrection(completion.id)
            },
            undo: { completionToUndo = completion }
          )
        }
      }
    }
    .confirmationDialog("Undo this workout?", item: $completionToUndo) { completion in
      Button("Undo Workout \(completion.workoutKey)", role: .destructive) {
        model.undoCompletionButtonTapped(completion.id)
      }
    } message: { _ in
      Text("This removes the workout and its saved exercise snapshot.")
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
        .buttonStyle(.borderless)
      if isLatest {
        Button("Undo this completion", role: .destructive, action: undo)
          .font(.subheadline)
          .buttonStyle(.borderless)
      }
    }
    .padding(.vertical, 4)
  }
}

private struct DateCorrectionScreen: View {
  @Bindable var model: WorkoutScreenModel
  var completionID: Completion.ID
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Form {
      DatePicker("Completed", selection: $model.dateDraft, in: ...model.now, displayedComponents: .date)
    }
    .navigationTitle("Change Date")
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          if model.saveCorrectedDateButtonTapped(for: completionID) {
            dismiss()
          }
        }
      }
    }
  }
}
