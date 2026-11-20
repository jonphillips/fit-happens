import CloudSyncKit
import FitHappensCore
import FitHappensInboxKit
import SwiftUI

struct ProgramImportScreen: View {
  @Environment(ChatInboxModel.self) private var chatInbox
  @State private var model = ProgramImportModel()
  var exportModel: ChatAccessExportModel
  var iCloudSyncModel: ICloudSyncModel
  var automaticBackupModel: AutomaticBackupModel

  var body: some View {
    NavigationStack(path: $model.path) {
      importForm
        .navigationTitle("Program")
        .navigationDestination(for: ProgramImportRoute.self) { _ in
          reviewScreen
        }
    }
  }

  private var importForm: some View {
    Form {
      stagedProgramsSection
      programSections
      pasteSection
      instructionsSection
      chatAccessSection
      ICloudSection(syncModel: iCloudSyncModel, automaticBackupModel: automaticBackupModel)
      revisionsSection
    }
  }

  private var stagedProgramsSection: some View {
    Group {
      if !chatInbox.rows.isEmpty || chatInbox.message != nil {
        Section("From Chat") {
          ForEach(chatInbox.rows) { row in
            stagedProgramRow(row, isNewest: chatInbox.rows.first?.id == row.id)
          }
          if let message = chatInbox.message {
            Text(message).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var programSections: some View {
    if let overview = model.programOverview {
      ForEach(overview.workouts) { workout in
        Section {
          ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, exercise in
            VStack(alignment: .leading, spacing: 3) {
              Text("\(index + 1). \(exercise.name)")
              Text(exercise.prescription).foregroundStyle(.secondary)
              if exercise.loadKind == .weight, let pounds = exercise.loadPounds {
                let label = exercise.loadLabel.map { " \($0)" } ?? ""
                Text("\(pounds.formatted(.number.precision(.fractionLength(0...2)))) lb\(label)")
                  .font(.subheadline).foregroundStyle(.secondary)
              } else {
                Text("Bodyweight").font(.subheadline).foregroundStyle(.secondary)
              }
            }
            .padding(.vertical, 2)
          }
        } header: {
          HStack {
            Text("Workout \(workout.key)")
            if workout.key == overview.nextWorkoutKey {
              Text("Next").font(.caption.weight(.semibold)).foregroundStyle(.tint)
            }
          }
        }
      }
    } else {
      Section("Program") {
        Text("No program yet.").foregroundStyle(.secondary)
      }
    }
  }

  private func stagedProgramRow(_ row: StagedProgramInboxRow, isNewest: Bool) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        Task {
          guard let text = await chatInbox.read(row) else {
            return
          }
          if let error = model.reviewStagedProgram(text, url: row.id) {
            chatInbox.setRowError(error, for: row.id)
          }
        }
      } label: {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text(row.stagedAt?.formatted(date: .abbreviated, time: .shortened) ?? row.snapshot.name)
              .foregroundStyle(.primary)
            Text(row.snapshot.isCurrent ? "Ready to review" : row.snapshot.downloadError ?? "Downloading…")
              .font(.caption)
              .foregroundStyle(.secondary)
            if isNewest { Text("Newest").font(.caption2).foregroundStyle(.tint) }
          }
          Spacer()
          Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(!row.snapshot.isCurrent)
      if let error = chatInbox.rowErrors[row.id] {
        Text(error).font(.caption).foregroundStyle(.red)
      }
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button("Discard", role: .destructive) { Task { await chatInbox.discard(row) } }
    }
  }

  private var chatAccessSection: some View {
    Section {
      Toggle("Chat Access", isOn: Binding(
        get: { exportModel.isEnabled },
        set: {
          exportModel.enabledChanged($0)
          chatInbox.enabledChanged($0)
        }
      ))
      if exportModel.isEnabled {
        Button("Refresh", systemImage: "arrow.clockwise") {
          exportModel.refreshButtonTapped()
        }
        if let lastExport = exportModel.lastExport {
          LabeledContent(
            "Last export",
            value: "\(lastExport.date.formatted(date: .abbreviated, time: .shortened)) · "
              + "\(lastExport.size.formatted()) bytes"
          )
        }
        if let exportStatus = exportModel.exportStatus {
          Text(exportStatus).font(.footnote).foregroundStyle(.secondary)
        }
      }
    } footer: {
      Text("Chat Access writes a read-only program, history, walks, and body-weight export to iCloud Drive.")
    }
  }

  private var pasteSection: some View {
    Section {
      TextEditor(text: $model.programText)
        .frame(minHeight: 190)
        .accessibilityLabel("Program contract")
      Button("Review Pasted Program", systemImage: "doc.text.magnifyingglass") {
        model.reviewPastedProgram()
      }
      .disabled(model.programText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .buttonStyle(.borderedProminent)
      if let errorMessage = model.errorMessage {
        Text(errorMessage)
          .foregroundStyle(.red)
          .accessibilityAddTraits(.isStaticText)
      }
    } header: {
      Text("Paste a program")
    } footer: {
      Text("The program is checked and shown for review before anything changes.")
    }
  }

  private var instructionsSection: some View {
    Section {
      Button("Copy instructions for ChatGPT", systemImage: "doc.on.doc") {
        model.copyInstructionsButtonTapped()
      }
      if model.instructionsCopied {
        Label("Instructions copied", systemImage: "checkmark")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var revisionsSection: some View {
    Section("Accepted revisions") {
      if model.acceptedRevisions.isEmpty {
        Text("Accepted programs will appear here.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(model.acceptedRevisions) { revision in
          Button {
            model.reviewRevision(revision)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(revision.acceptedAt, format: .dateTime.month().day().year().hour().minute())
                .foregroundStyle(.primary)
              Text("Review this revision")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  @ViewBuilder
  private var reviewScreen: some View {
    if let review = model.review {
      ProgramReviewScreen(review: review, errorMessage: model.errorMessage) {
        if let url = model.stagedURL {
          Task {
            guard await chatInbox.applyStagedProgram(url, applying: { model.applyReviewedProgram() }) else {
              return
            }
          }
        } else {
          _ = model.applyReviewedProgram()
        }
      }
    } else {
      ContentUnavailableView("Review unavailable", systemImage: "exclamationmark.triangle")
    }
  }
}

private struct ProgramReviewScreen: View {
  var review: ProgramReview
  var errorMessage: String?
  var apply: () -> Void

  var body: some View {
    List {
      if let warning = review.warning {
        Section("Check this program") {
          Label(warning, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
        }
      }

      ExerciseChangesSection(changes: review.changeSet)
      WorkoutChangesSection(changes: review.changeSet, proposedWorkouts: review.proposedWorkouts)

      if let errorMessage {
        Section("Could not apply") {
          Text(errorMessage).foregroundStyle(.red)
        }
      }
    }
    .navigationTitle("Review Changes")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Apply", systemImage: "checkmark") { apply() }
          .fontWeight(.semibold)
      }
    }
  }
}

private struct ExerciseChangesSection: View {
  var changes: ProgramChangeSet

  var hasChanges: Bool {
    !changes.addedExercises.isEmpty || !changes.retiredExerciseKeys.isEmpty
      || !changes.restoredExerciseKeys.isEmpty || !changes.renames.isEmpty
      || !changes.loadKindChanges.isEmpty || !changes.carriedWeights.isEmpty
      || !changes.ignoredStartingWeights.isEmpty || !changes.weightChanges.isEmpty
      || !changes.ignoredNewWeights.isEmpty || !changes.incrementChanges.isEmpty
      || !changes.loadLabelChanges.isEmpty || !changes.notesChanges.isEmpty
  }

  var body: some View {
    Section("Exercises") {
      if !hasChanges {
        Text("No exercise changes.").foregroundStyle(.secondary)
      }
      ExerciseChangeRows(changes: changes)
    }
  }
}

private struct ExerciseChangeRows: View {
  var changes: ProgramChangeSet

  var body: some View {
    rows
  }

  @ViewBuilder
  private var rows: some View {
    ForEach(changes.addedExercises, id: \.key) { exercise in
        LabeledContent("Added", value: "\(exercise.name) · \(exercise.key)")
        if exercise.loadKind == .weight, let pounds = exercise.startingWeight {
          LabeledContent("Starting weight", value: "\(pounds.formatted()) lb")
        }
    }
    ForEach(changes.retiredExerciseKeys, id: \.self) { key in
      LabeledContent("Retired", value: key)
    }
    ForEach(changes.restoredExerciseKeys, id: \.self) { key in
      LabeledContent("Restored", value: key)
    }
    ForEach(changes.renames, id: \.key) { rename in
      LabeledContent("Renamed · \(rename.key)", value: "\(rename.oldName) → \(rename.newName)")
    }
    ForEach(changes.loadKindChanges, id: \.exerciseKey) { change in
      LabeledContent(
        "Load · \(change.exerciseKey)", value: "\(change.oldKind.rawValue) → \(change.newKind.rawValue)"
      )
    }
    ForEach(changes.weightChanges, id: \.exerciseKey) { change in
      LabeledContent(
        "Weight · \(change.exerciseKey)",
        value: "\(change.oldPounds.formatted()) → \(change.newPounds.formatted()) lb"
      )
    }
    ForEach(changes.ignoredNewWeights, id: \.exerciseKey) { ignored in
      LabeledContent(
        "New weight ignored · \(ignored.exerciseKey)",
        value: "\(ignored.proposedPounds.formatted()) lb proposed; "
          + "\(ignored.keptLoad.reviewDescription) kept"
      )
    }
    ForEach(changes.carriedWeights, id: \.exerciseKey) { carryover in
      LabeledContent("Weight kept · \(carryover.exerciseKey)", value: carryover.load.reviewDescription)
    }
    ForEach(changes.ignoredStartingWeights, id: \.exerciseKey) { ignored in
      LabeledContent(
        "Starting weight ignored · \(ignored.exerciseKey)",
        value: "\(ignored.proposedPounds.formatted()) lb proposed; \(ignored.keptLoad.reviewDescription) kept"
      )
    }
    ForEach(changes.incrementChanges, id: \.exerciseKey) { change in
      LabeledContent(
        "Increment · \(change.exerciseKey)",
        value: "\(change.oldPounds.formatted()) → \(change.newPounds.formatted()) lb"
      )
    }
    ForEach(changes.loadLabelChanges, id: \.exerciseKey) { change in
      LabeledContent(
        "Load label · \(change.exerciseKey)",
        value: "\(change.oldValue ?? "none") → \(change.newValue ?? "none")"
      )
    }
    ForEach(changes.notesChanges, id: \.exerciseKey) { change in
      LabeledContent(
        "Notes · \(change.exerciseKey)",
        value: "\(change.oldValue ?? "none") → \(change.newValue ?? "none")"
      )
    }
  }
}

private struct WorkoutChangesSection: View {
  var changes: ProgramChangeSet
  var proposedWorkouts: [ProgramWorkout]

  var hasChanges: Bool {
    !changes.addedWorkouts.isEmpty || !changes.removedWorkoutKeys.isEmpty
      || changes.workoutOrderChanged || !changes.workoutChanges.isEmpty
  }

  var body: some View {
    Section("Workouts") {
      LabeledContent("Program order", value: proposedWorkouts.map(\.key).joined(separator: " → "))
      if !hasChanges {
        Text("No workout changes.").foregroundStyle(.secondary)
      }
      ForEach(changes.addedWorkouts, id: \.key) { workout in
        AddedWorkoutReviewRow(workout: workout)
      }
      ForEach(changes.removedWorkoutKeys, id: \.self) { key in
        LabeledContent("Removed workout", value: key)
      }
      if changes.workoutOrderChanged {
        Label("Workout order changed", systemImage: "arrow.up.arrow.down")
      }
      ForEach(changes.workoutChanges, id: \.workoutKey) { change in
        WorkoutMembershipChangeRow(change: change)
      }
    }
  }
}

private struct AddedWorkoutReviewRow: View {
  var workout: ProgramWorkout

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Added workout \(workout.key)")
        .font(.headline)
      ForEach(workout.items, id: \.key) { item in
        let prescription = item.ramp.map(ProgramPrescriptionResolver.relative) ?? item.prescription
        Text("\(item.key) · \(prescription) · \(item.loadKind.rawValue)")
        if item.loadKind == .weight, let startingWeight = item.startingWeight {
          Text("Starting weight: \(startingWeight.formatted()) lb")
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

private struct WorkoutMembershipChangeRow: View {
  var change: WorkoutMembershipChange

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Workout \(change.workoutKey)")
        .font(.headline)
      if change.orderChanged {
        Text("Exercise order changed")
      }
      ForEach(change.addedItems, id: \.exerciseKey) { item in
        Text("Added \(item.exerciseKey) · \(item.prescription)")
      }
      ForEach(change.removedExerciseKeys, id: \.self) { key in
        Text("Removed \(key)")
      }
      ForEach(change.prescriptionChanges, id: \.exerciseKey) { prescription in
        Text("\(prescription.exerciseKey): \(prescription.oldPrescription) → \(prescription.newPrescription)")
      }
    }
    .font(.subheadline)
  }
}

private extension Load {
  var reviewDescription: String {
    switch self {
    case let .weight(pounds): "\(pounds.formatted()) lb"
    case .bodyweight: "bodyweight"
    }
  }
}
