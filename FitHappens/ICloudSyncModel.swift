import CloudKit
import CloudSyncKit
import Dependencies
import FitHappensCore
import Observation
import SQLiteData

@MainActor
@Observable
final class ICloudSyncModel {
  private(set) var health = SyncHealth(
    isManuallyEnabled: false,
    account: .couldNotDetermine,
    isEngineRunning: false,
    pendingChangeCount: 0
  )

  @ObservationIgnored private var lastStartError: String?
  @ObservationIgnored private var pendingReadError: String?
  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.defaultSyncEngine) private var syncEngine

  var isEnabled: Bool { FitHappensCloudSync.isManuallyEnabled() }
  var isDisabledByRestore: Bool { FitHappensCloudSync.isDisabledByRestore() }
  var statusText: String { health.displayStatus.summary }
  var isSynchronizing: Bool { syncEngine.isSynchronizing }

  func refresh() async {
    let isEnabled = FitHappensCloudSync.isManuallyEnabled()
    let isEngineRunning = syncEngine.isRunning
    let account: SyncAccountStatus
    do {
      let status = try await CKContainer(identifier: FitHappensCloudSync.configuration.containerIdentifier)
        .accountStatus()
      account = SyncAccountStatus(status)
    } catch {
      account = .couldNotDetermine
    }

    let pendingChangeCount: Int
    if isEnabled {
      do {
        pendingChangeCount = try await CloudSync.pendingRecordZoneChangeCount(in: database)
        pendingReadError = nil
      } catch {
        pendingChangeCount = 0
        pendingReadError = "Could not read pending sync changes."
      }
    } else {
      pendingChangeCount = 0
      pendingReadError = nil
    }

    health = SyncHealth(
      isManuallyEnabled: isEnabled,
      account: account,
      isEngineRunning: isEngineRunning,
      pendingChangeCount: pendingChangeCount,
      isFetchingChanges: isEngineRunning && syncEngine.isFetchingChanges,
      lastError: lastStartError ?? pendingReadError
    )
  }

  func enabledChanged(_ enabled: Bool) async {
    FitHappensCloudSync.setManuallyEnabled(enabled)
    if enabled {
      await start()
    } else {
      syncEngine.stop()
      lastStartError = nil
      await refresh()
    }
  }

  func startIfEnabled() async {
    if FitHappensCloudSync.isManuallyEnabled(), !syncEngine.isRunning {
      await start()
    } else {
      await refresh()
    }
  }

  private func start() async {
    switch await FitHappensCloudSync.startIfManuallyEnabled() {
    case let .failed(message): lastStartError = message
    case .started, .disabled, .unavailable: lastStartError = nil
    }
    await refresh()
  }
}
