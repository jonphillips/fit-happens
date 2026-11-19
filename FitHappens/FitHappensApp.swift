import Dependencies
import FitHappensCore
import SwiftUI

@main
struct FitHappensApp: App {
  @State private var selectedTab = AppTab.workout

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
        WorkoutScreen()
          .tabItem { Label("Next Workout", systemImage: "dumbbell.fill") }
          .tag(AppTab.workout)
        ActivityScreen(isActive: selectedTab == .activity)
          .tabItem { Label("Activity", systemImage: "calendar") }
          .tag(AppTab.activity)
      }
    }
  }
}

private enum AppTab: Hashable {
  case workout
  case activity
}
