import Dependencies
import FitHappensCore
import SwiftUI

@main
struct FitHappensApp: App {
  init() {
    UserDefaults.standard.register(defaults: [FitHappensCloudSync.configuration.enabledDefaultsKey: true])
    do {
      try prepareDependencies {
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
      WorkoutScreen()
    }
  }
}
