import ChatAccessKit
import Dependencies
import FitHappensCore
import FitHappensInboxKit
import Foundation
import Sharing
import SQLiteData
import UIKit

struct ChatAccessBackgroundTaskClient: Sendable {
  var begin: @MainActor @Sendable (_ name: String, _ onExpire: @escaping @MainActor @Sendable () -> Void) -> Int
  var end: @MainActor @Sendable (Int) -> Void

  static func live(application: UIApplication) -> Self {
    Self(
      begin: { name, onExpire in
        let identifier = application.beginBackgroundTask(withName: name) {
          Task { @MainActor in onExpire() }
        }
        return identifier.rawValue
      },
      end: { application.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: $0)) }
    )
  }
}

@MainActor
private final class ChatAccessExportAssertion {
  private var identifier = UIBackgroundTaskIdentifier.invalid.rawValue
  private let client: ChatAccessBackgroundTaskClient

  init(client: ChatAccessBackgroundTaskClient) {
    self.client = client
  }

  func begin(onExpire: @escaping @MainActor @Sendable () -> Void) -> Bool {
    identifier = client.begin("FitHappensChatAccessExport", onExpire)
    return identifier != UIBackgroundTaskIdentifier.invalid.rawValue
  }

  func end() {
    guard identifier != UIBackgroundTaskIdentifier.invalid.rawValue else {
      return
    }
    let current = identifier
    identifier = UIBackgroundTaskIdentifier.invalid.rawValue
    client.end(current)
  }
}

private struct ChatExportRows: Sendable {
  var exercises: [Exercise]
  var workouts: [Workout]
  var workoutItems: [WorkoutItem]
  var completions: [Completion]
  var completionItems: [CompletionItem]

  static func fetch(in database: Database) throws -> Self {
    Self(
      exercises: try Exercise.all.fetchAll(database),
      workouts: try Workout.all.fetchAll(database),
      workoutItems: try WorkoutItem.all.fetchAll(database),
      completions: try Completion.all.fetchAll(database),
      completionItems: try CompletionItem.all.fetchAll(database)
    )
  }
}

@MainActor
@Observable
final class ChatAccessExportModel {
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.healthClient) private var healthClient
  @ObservationIgnored @Dependency(\.chatAccessContainer) private var folderClient
  @ObservationIgnored @Shared(.appStorage("fitHappensChatAccessEnabled"))
  private var chatAccessEnabled = false
  @ObservationIgnored private let writer = ChatAccessExportWriter()
  @ObservationIgnored private let backgroundTaskClient: ChatAccessBackgroundTaskClient
  @ObservationIgnored private var task: Task<Void, Never>?

  var exportStatus: String?
  private(set) var isRefreshing = false

  init(
    application: UIApplication = .shared,
    backgroundTaskClient: ChatAccessBackgroundTaskClient? = nil
  ) {
    self.backgroundTaskClient = backgroundTaskClient ?? .live(application: application)
  }

  var isEnabled: Bool { chatAccessEnabled }
  var lastExport: ChatAccessExportWriter.LastExport? { writer.lastExport }

  func enabledChanged(_ enabled: Bool) {
    $chatAccessEnabled.withLock { $0 = enabled }
    exportStatus = nil
    if enabled {
      start(force: true)
    } else {
      task?.cancel()
    }
  }

  func refreshButtonTapped() {
    start(force: true)
  }

  func appDidEnterBackground() {
    start(force: false)
  }

  private func start(force: Bool) {
    guard chatAccessEnabled, !isRefreshing else {
      return
    }
    if !force, !writer.isDue(at: now) {
      return
    }

    isRefreshing = true
    exportStatus = nil
    let assertion = ChatAccessExportAssertion(client: backgroundTaskClient)
    let didBegin = assertion.begin { [weak self, weak assertion] in
      self?.task?.cancel()
      self?.task = nil
      self?.isRefreshing = false
      assertion?.end()
    }
    guard didBegin else {
      isRefreshing = false
      exportStatus = "Fit Happens couldn't start a background task for the export. Try Refresh again."
      return
    }

    task = Task { [weak self] in
      guard let self else {
        assertion.end()
        return
      }
      await self.performExport(force: force, assertion: assertion)
    }
  }

  private func performExport(force: Bool, assertion: ChatAccessExportAssertion) async {
    defer {
      assertion.end()
      isRefreshing = false
      task = nil
    }
    do {
      try Task.checkCancellation()
      let folder = try await folderClient.resolveFolder()
      try Task.checkCancellation()
      let rows = try await database.read { database in
        try ChatExportRows.fetch(in: database)
      }
      let generatedAt = now
      let health = await readHealth(
        from: generatedAt.addingTimeInterval(-365 * 86_400), through: generatedAt
      )
      try Task.checkCancellation()
      let data = try await encodeExport(rows: rows, health: health, generatedAt: generatedAt)
      try Task.checkCancellation()
      let result = try await writer.write(data, to: folder, generatedAt: generatedAt, force: force)
      switch result {
      case .written, .throttled:
        exportStatus = nil
      case .alreadyWriting:
        exportStatus = "An export is already being written."
      }
    } catch is CancellationError {
      // The background assertion expired or Chat Access was switched off.
    } catch {
      if chatAccessEnabled, !Task.isCancelled {
        exportStatus = error.localizedDescription
      }
    }
  }

  private func encodeExport(
    rows: ChatExportRows,
    health: (walks: [HealthWalkingWorkout], bodyMass: [HealthBodyMass]),
    generatedAt: Date
  ) async throws -> Data {
    let device = UIDevice.current.model
    let calendar = Calendar.current
    let buildTask = Task.detached(priority: .utility) {
      let program = try CurrentProgramQuery.make(
        exerciseRows: rows.exercises, workoutRows: rows.workouts, itemRows: rows.workoutItems
      )
      let export = FitHappensChatExportBuilder.make(
        program: program, completions: rows.completions, completionItems: rows.completionItems,
        exercises: rows.exercises, walks: health.walks, bodyMass: health.bodyMass,
        generatedAt: generatedAt, device: device, calendar: calendar
      )
      try Task.checkCancellation()
      return try export.encoded()
    }
    return try await withTaskCancellationHandler {
      try await buildTask.value
    } onCancel: {
      buildTask.cancel()
    }
  }

  private func readHealth(
    from start: Date, through end: Date
  ) async -> (walks: [HealthWalkingWorkout], bodyMass: [HealthBodyMass]) {
    do {
      async let walks = healthClient.walkingWorkouts(start, end)
      async let bodyMass = healthClient.bodyMassSamples(start, end)
      return try await (walks, bodyMass)
    } catch {
      return ([], [])
    }
  }
}
