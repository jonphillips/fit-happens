import ChatAccessKit
import Dependencies
import FitHappensCore
import Foundation
import Sharing
import SQLiteData
import UIKit

@MainActor
@Observable
final class ChatAccessExportModel {
  @ObservationIgnored @Dependency(\.date) private var date
  @ObservationIgnored @Dependency(\.healthClient) private var healthClient
  @ObservationIgnored @FetchAll(Exercise.all) private var exercises
  @ObservationIgnored @FetchAll(Workout.all) private var workouts
  @ObservationIgnored @FetchAll(WorkoutItem.all) private var workoutItems
  @ObservationIgnored @FetchAll(Completion.all) private var completions
  @ObservationIgnored @FetchAll(CompletionItem.all) private var completionItems
  @ObservationIgnored @Shared(.appStorage("fitHappensChatAccessEnabled"))
  private var chatAccessEnabled = false

  private let writer = ChatAccessExportWriter()
  var exportStatus: String?

  var isEnabled: Bool { chatAccessEnabled }
  var lastExport: ChatAccessExportWriter.LastExport? { writer.lastExport }

  func enabledChanged(_ enabled: Bool) {
    $chatAccessEnabled.withLock { $0 = enabled }
    exportStatus = nil
    if enabled {
      Task { await writeExport(force: true) }
    }
  }

  func refreshButtonTapped() async {
    await writeExport(force: true)
  }

  func appDidEnterBackground() async {
    await writeExport(force: false)
  }

  private func writeExport(force: Bool) async {
    guard chatAccessEnabled else {
      return
    }
    guard let containerURL = FileManager.default.url(
      forUbiquityContainerIdentifier: "iCloud.com.jonphillips.fithappens"
    ) else {
      exportStatus = "iCloud Drive is unavailable."
      return
    }
    let now = date.now
    let cutoff = Calendar.current.date(byAdding: .day, value: -365, to: now) ?? .distantPast
    let health = await readHealth(cutoff: cutoff, through: now)
    guard chatAccessEnabled else {
      return
    }
    do {
      let program = try CurrentProgramQuery.make(
        exerciseRows: exercises, workoutRows: workouts, itemRows: workoutItems
      )
      let export = FitHappensChatExportBuilder.make(
        program: program, completions: completions, completionItems: completionItems,
        exercises: exercises, walks: health.walks, bodyMass: health.bodyMass,
        generatedAt: now, device: UIDevice.current.model
      )
      let folder = ChatAccessFolder(containerURL: containerURL, isDevelopment: false)
      let result = try await writer.write(export.encoded(), to: folder, generatedAt: now, force: force)
      switch result {
      case let .written(date, size), let .throttled(date, size):
        exportStatus = "Updated \(date.formatted(date: .abbreviated, time: .shortened)) · "
          + "\(size.formatted()) bytes"
      case .alreadyWriting:
        exportStatus = "An export is already being written."
      }
    } catch {
      exportStatus = "Could not write the chat export: \(error.localizedDescription)"
    }
  }

  private func readHealth(
    cutoff: Date, through end: Date
  ) async -> (walks: [HealthWalkingWorkout], bodyMass: [HealthBodyMass]) {
    do {
      async let walks = healthClient.walkingWorkouts(cutoff, end)
      async let bodyMass = healthClient.bodyMassSamples(cutoff, end)
      return try await (walks, bodyMass)
    } catch {
      return ([], [])
    }
  }
}
