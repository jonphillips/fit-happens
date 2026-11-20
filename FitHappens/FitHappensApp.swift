import Dependencies
import FitHappensCore
import FitHappensInboxKit
import SwiftUI

@main
struct FitHappensApp: App {
  @State private var selectedTab = AppTab.workout
  @State private var chatInbox = ChatInboxModel()
  @State private var chatAccessModel = ChatAccessExportModel()
  @State private var correctionsModel = CompletionCorrectionsModel()
  @Environment(\.scenePhase) private var scenePhase

  init() {
    UserDefaults.standard.register(defaults: [FitHappensCloudSync.configuration.enabledDefaultsKey: true])
    do {
      try prepareDependencies {
        $0.healthClient = HealthKitClient.live
        try $0.bootstrapDatabase()
      }
    } catch {
      fatalError("Database bootstrap failed: \(error)")
    }
    FitHappensCloudSync.persistManualEnablementFromLaunchEnvironment()
    Task { _ = await FitHappensCloudSync.startIfManuallyEnabled() }
  }

  var body: some Scene {
    WindowGroup {
      TabView(selection: $selectedTab) {
        Tab("Next Workout", systemImage: "dumbbell.fill", value: AppTab.workout) {
          WorkoutScreen(selectedTab: $selectedTab)
        }
        Tab("Activity", systemImage: "calendar", value: AppTab.activity) {
          ActivityScreen(isActive: selectedTab == .activity)
        }
        Tab("Program", systemImage: "doc.text", value: AppTab.program) {
          ProgramImportScreen(exportModel: chatAccessModel)
        }
        .badge(chatInbox.readyCount > 0 ? Text(chatInbox.readyCount.formatted()) : nil)
      }
      .environment(chatInbox)
      .environment(correctionsModel)
      .task { await chatInbox.prepare() }
      .onChange(of: scenePhase) { _, phase in
        guard phase == .active else {
          return
        }
        Task { await chatInbox.prepare() }
      }
      .onChange(of: scenePhase) { _, phase in
        guard phase == .background else {
          return
        }
        chatAccessModel.appDidEnterBackground()
      }
    }
  }
}

enum AppTab: Hashable {
  case workout
  case activity
  case program
}
