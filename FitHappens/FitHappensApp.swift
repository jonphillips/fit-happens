import CloudSyncKit
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
  @State private var iCloudSyncModel = ICloudSyncModel()
  @State private var automaticBackupModel = AutomaticBackupModel(
    backup: FitHappensCloudSync.databaseBackupConfiguration,
    configuration: FitHappensCloudSync.automaticBackupConfiguration
  )

  init() {
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
      FitHappensScene(
        selectedTab: $selectedTab,
        chatInbox: chatInbox,
        chatAccessModel: chatAccessModel,
        correctionsModel: correctionsModel,
        iCloudSyncModel: iCloudSyncModel,
        automaticBackupModel: automaticBackupModel
      )
    }
  }
}

private struct FitHappensScene: View {
  @Binding var selectedTab: AppTab
  var chatInbox: ChatInboxModel
  var chatAccessModel: ChatAccessExportModel
  var correctionsModel: CompletionCorrectionsModel
  var iCloudSyncModel: ICloudSyncModel
  var automaticBackupModel: AutomaticBackupModel
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    TabView(selection: $selectedTab) {
      Tab("Next Workout", systemImage: "dumbbell.fill", value: AppTab.workout) {
        WorkoutScreen(selectedTab: $selectedTab)
      }
      Tab("Activity", systemImage: "calendar", value: AppTab.activity) {
        ActivityScreen(isActive: selectedTab == .activity)
      }
      Tab("Program", systemImage: "doc.text", value: AppTab.program) {
        ProgramImportScreen(
          exportModel: chatAccessModel,
          iCloudSyncModel: iCloudSyncModel,
          automaticBackupModel: automaticBackupModel
        )
      }
      .badge(chatInbox.readyCount)
    }
    .environment(chatInbox)
    .environment(correctionsModel)
    .task { await chatInbox.prepare() }
    .task { await automaticBackupModel.runIfDue() }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else {
        return
      }
      Task { await sceneBecameActive() }
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .background else {
        return
      }
      chatAccessModel.appDidEnterBackground()
    }
  }

  private func sceneBecameActive() async {
    await chatInbox.prepare()
    await iCloudSyncModel.startIfEnabled()
    await automaticBackupModel.runIfDue()
  }
}

enum AppTab: Hashable {
  case workout
  case activity
  case program
}
