import ChatAccessKit
import Dependencies
import Foundation
import LLMHandoffKit
import Observation
import Sharing

struct StagedProgramInboxRow: Identifiable, Equatable, Sendable {
  var snapshot: ChatInboxSnapshot
  var id: URL { snapshot.url }
  var stagedAt: Date? { StagedHandoff(url: snapshot.url)?.stagedAt }
}

@MainActor
@Observable
final class ChatInboxModel {
  static let kind = ChatInboxItemKind(fileExtension: "fhprogram", expiresUnclaimed: true, datesProcessedByClaim: true)

  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.chatAccessContainer) private var container
  @ObservationIgnored @Dependency(\.chatInboxFiles) private var files
  @ObservationIgnored @Shared(.appStorage("fitHappensChatAccessEnabled")) private var isEnabled = false
  @ObservationIgnored private var watcher: ChatInboxWatcher?
  @ObservationIgnored private var watcherTask: Task<Void, Never>?
  @ObservationIgnored private var folder: ChatAccessFolder?
  @ObservationIgnored private var generation = 0
  private var snapshots: [ChatInboxSnapshot] = []
  private(set) var enabledState = UserDefaults.standard.bool(forKey: "fitHappensChatAccessEnabled")
  private(set) var message: String?
  private(set) var rowErrors: [URL: String] = [:]

  isolated deinit {
    watcher?.stop()
    watcherTask?.cancel()
  }

  var enabled: Bool { enabledState }
  var rows: [StagedProgramInboxRow] {
    guard enabledState else {
      return []
    }
    return snapshots.filter { $0.url.pathExtension == Self.kind.fileExtension }
      .map(StagedProgramInboxRow.init(snapshot:))
  }
  var readyCount: Int { rows.filter(\.snapshot.isCurrent).count }

  func enabledChanged(_ value: Bool) {
    $isEnabled.withLock { $0 = value }
    enabledState = value
    if value { Task { await prepare() } } else { stop() }
  }

  func prepare() async {
    guard enabledState else {
      return
    }
    let currentGeneration = generation
    do {
      let folder = try await container.resolveAndCreateInbox()
      guard enabledState, generation == currentGeneration else {
        return
      }
      self.folder = folder
      if watcher == nil {
        let watcher = ChatInboxWatcher(folder: folder)
        self.watcher = watcher
        watcher.start()
        watcherTask = Task { [weak self] in
          for await snapshots in watcher.snapshots { self?.receive(snapshots) }
        }
      }
      try await files.maintain(folder, [Self.kind], now)
      message = nil
    } catch {
      guard enabledState, generation == currentGeneration else {
        return
      }
      message = error.localizedDescription
    }
  }

  func read(_ row: StagedProgramInboxRow) async -> String? {
    guard row.snapshot.isCurrent else {
      return nil
    }
    do {
      let text = try await files.read(row.snapshot.url)
      rowErrors[row.id] = nil
      return text
    } catch {
      rowErrors[row.id] = error.localizedDescription
      return nil
    }
  }

  func claim(_ url: URL) async {
    guard let folder else {
      return
    }
    do {
      try await files.claim(folder, url, Self.kind)
      forget(url)
    } catch HandoffInboxError.alreadyClaimed {
      forget(url)
    } catch {
      rowErrors[url] = error.localizedDescription
    }
  }

  func discard(_ row: StagedProgramInboxRow) async {
    await claim(row.id)
  }

  private func receive(_ values: [ChatInboxSnapshot]) {
    snapshots = values.filter { $0.url.pathExtension == Self.kind.fileExtension }
  }

  private func forget(_ url: URL) {
    snapshots.removeAll { $0.url == url }
    rowErrors[url] = nil
  }

  private func stop() {
    generation += 1
    watcher?.stop()
    watcher = nil
    watcherTask?.cancel()
    watcherTask = nil
    folder = nil
    snapshots = []
    rowErrors = [:]
    message = nil
  }
}

private enum ChatInboxFilesKey: DependencyKey {
  static let liveValue: ChatInboxFileClient = .live
}

extension DependencyValues {
  var chatInboxFiles: ChatInboxFileClient {
    get { self[ChatInboxFilesKey.self] }
    set { self[ChatInboxFilesKey.self] = newValue }
  }
}
