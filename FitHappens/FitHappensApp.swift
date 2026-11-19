import Dependencies
import FitHappensCore
import FitHappensInboxKit
import SwiftUI

@main
struct FitHappensApp: App {
  @State private var selectedTab = AppTab.workout
  @State private var chatInbox = ChatInboxModel()
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
          WorkoutScreen()
        }
        Tab("Activity", systemImage: "calendar", value: AppTab.activity) {
          ActivityScreen(isActive: selectedTab == .activity)
        }
      }
      .environment(chatInbox)
      .task { await chatInbox.prepare() }
      .onChange(of: scenePhase) { _, phase in
        guard phase == .active else {
          return
        }
        Task { await chatInbox.prepare() }
      }
    }
  }
}

private enum AppTab: Hashable {
  case workout
  case activity
}
