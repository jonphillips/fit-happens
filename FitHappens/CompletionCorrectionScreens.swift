import FitHappensCore
import SwiftUI

enum ActivityDestination: Hashable {
  case history
  case correctDate(Completion.ID)
}

struct CompletionHistoryScreen: View {
  var model: CompletionCorrectionsModel
  @Binding var path: [ActivityDestination]
  @State private var completionToUndo: Completion?

  var body: some View {
    List {
      if model.history.isEmpty {
        ContentUnavailableView("No workouts yet", systemImage: "clock")
      } else {
        ForEach(model.history) { completion in
          CompletionHistoryRow(
            completion: completion,
            isLatest: completion.id == model.latestCompletionID,
            changeDate: { path.append(.correctDate(completion.id)) },
            undo: { completionToUndo = completion }
          )
        }
      }
    }
    .navigationTitle("Fix a Workout")
    .confirmationDialog("Undo this workout?", item: $completionToUndo) { completion in
      Button("Undo Workout \(completion.workoutKey)", role: .destructive) {
        model.undoCompletionButtonTapped(completion.id)
      }
    } message: { _ in
      Text("This removes the workout and its saved exercise snapshot.")
    }
  }
}

struct LatestCompletionCorrectionScreen: View {
  var model: CompletionCorrectionsModel
  @State private var path: [Completion.ID] = []
  @State private var completionToUndo: Completion?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack(path: $path) {
      latestCompletionContent
    }
  }

  private var latestCompletionContent: some View {
    List {
      if let completion = model.latestCompletion {
        Section("Workout \(completion.workoutKey)") {
          LabeledContent("Completed", value: completion.completedAt.formatted(date: .long, time: .omitted))
          Button("Change date") {
            model.changeDateButtonTapped(for: completion)
            path.append(completion.id)
          }
          Button("Undo Workout \(completion.workoutKey)", role: .destructive) {
            completionToUndo = completion
          }
        }
      }
    }
    .navigationTitle("Last done")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") { dismiss() }
      }
    }
    .navigationDestination(for: Completion.ID.self) { completionID in
      CompletionDateCorrectionScreen(model: model, completionID: completionID)
    }
    .confirmationDialog("Undo this workout?", item: $completionToUndo) { completion in
      Button("Undo Workout \(completion.workoutKey)", role: .destructive) {
        model.undoCompletionButtonTapped(completion.id)
        dismiss()
      }
    } message: { _ in
      Text("This removes the workout and its saved exercise snapshot.")
    }
  }
}

private struct CompletionHistoryRow: View {
  var completion: Completion
  var isLatest: Bool
  var changeDate: () -> Void
  var undo: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Workout \(completion.workoutKey)").font(.headline)
        Spacer()
        Text(completion.completedAt, format: .dateTime.month().day().year()).foregroundStyle(.secondary)
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

struct CompletionDateCorrectionScreen: View {
  @Bindable var model: CompletionCorrectionsModel
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
          if model.saveCorrectedDateButtonTapped(for: completionID) { dismiss() }
        }
      }
    }
  }
}

struct CompletionDateCorrectionDestination: View {
  var model: CompletionCorrectionsModel
  var completionID: Completion.ID

  var body: some View {
    Group {
      if let completion = model.history.first(where: { $0.id == completionID }) {
        CompletionDateCorrectionScreen(model: model, completionID: completionID)
          .onAppear { model.changeDateButtonTapped(for: completion) }
      } else {
        ContentUnavailableView("Workout not found", systemImage: "exclamationmark.triangle")
      }
    }
  }
}
