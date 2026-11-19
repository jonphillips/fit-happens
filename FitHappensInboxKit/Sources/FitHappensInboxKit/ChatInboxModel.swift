import ChatAccessKit
import Dependencies
import Foundation
import LLMHandoffKit
import Observation
import Sharing

public struct StagedProgramInboxRow: Identifiable, Equatable, Sendable {
  public var snapshot: ChatInboxSnapshot
  public var id: URL { snapshot.url }
  public var stagedAt: Date? { StagedHandoff(url: snapshot.url)?.stagedAt }

  public init(snapshot: ChatInboxSnapshot) {
    self.snapshot = snapshot
  }
}

@MainActor
@Observable
public final class ChatInboxModel {
  static let kind = ChatInboxItemKind(fileExtension: "fhprogram", expiresUnclaimed: true, datesProcessedByClaim: true)

  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.chatAccessContainer) private var container
  @ObservationIgnored @Dependency(\.chatInboxFiles) private var files
  @ObservationIgnored @Dependency(\.chatInboxWatcher) private var makeWatcher
  @ObservationIgnored @Shared(.appStorage("fitHappensChatAccessEnabled")) private var isEnabled = false
  @ObservationIgnored private var watcher: ChatInboxObservation?
  @ObservationIgnored private var watcherTask: Task<Void, Never>?
  @ObservationIgnored private var folder: ChatAccessFolder?
  @ObservationIgnored private var generation = 0
  private var snapshots: [ChatInboxSnapshot] = []
  private var claimed: Set<URL> = []
  public private(set) var message: String?
  public private(set) var rowErrors: [URL: String] = [:]

  public init() {}

  isolated deinit {
    watcher?.stop()
    watcherTask?.cancel()
  }

  public var enabled: Bool { isEnabled }
  public var rows: [StagedProgramInboxRow] {
    guard isEnabled else {
      return []
    }
    return snapshots.map(StagedProgramInboxRow.init(snapshot:))
  }
  public var readyCount: Int { rows.filter(\.snapshot.isCurrent).count }

  public func enabledChanged(_ value: Bool) {
    $isEnabled.withLock { $0 = value }
    if value { Task { await prepare() } } else { stop() }
  }

  public func prepare() async {
    guard isEnabled else {
      return
    }
    let currentGeneration = generation
    do {
      let folder = try await container.resolveAndCreateInbox()
      guard isEnabled, generation == currentGeneration else {
        return
      }
      self.folder = folder
      if watcher == nil {
        let watcher = makeWatcher(folder)
        self.watcher = watcher
        watcherTask = Task { [weak self] in
          for await snapshots in watcher.snapshots { self?.receive(snapshots) }
        }
      }
      try await files.maintain(folder, [Self.kind], now)
      message = nil
    } catch {
      guard isEnabled, generation == currentGeneration else {
        return
      }
      message = error.localizedDescription
    }
  }

  public func read(_ row: StagedProgramInboxRow) async -> String? {
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

  public func claim(_ url: URL) async {
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

  public func discard(_ row: StagedProgramInboxRow) async {
    await claim(row.id)
  }

  public func applyStagedProgram(_ url: URL, applying apply: () -> Bool) async -> Bool {
    guard apply() else {
      return false
    }
    await claim(url)
    return true
  }

  public func setRowError(_ error: String, for url: URL) {
    rowErrors[url] = error
  }

  private func receive(_ values: [ChatInboxSnapshot]) {
    claimed.formIntersection(Set(values.map(\.url)))
    snapshots = values.filter {
      $0.url.pathExtension == Self.kind.fileExtension && !claimed.contains($0.url)
    }
  }

  private func forget(_ url: URL) {
    claimed.insert(url)
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
    claimed = []
    rowErrors = [:]
    message = nil
  }
}

public struct ChatInboxObservation: Sendable {
  public let snapshots: AsyncStream<[ChatInboxSnapshot]>
  public let stop: @MainActor @Sendable () -> Void

  public init(snapshots: AsyncStream<[ChatInboxSnapshot]>, stop: @escaping @MainActor @Sendable () -> Void) {
    self.snapshots = snapshots
    self.stop = stop
  }
}

private enum ChatInboxWatcherKey: DependencyKey {
  static var liveValue: @MainActor @Sendable (ChatAccessFolder) -> ChatInboxObservation {
    { folder in
      let watcher = ChatInboxWatcher(folder: folder)
      watcher.start()
      return ChatInboxObservation(snapshots: watcher.snapshots, stop: { watcher.stop() })
    }
  }
}

private enum ChatInboxFilesKey: DependencyKey {
  static let liveValue: ChatInboxFileClient = .live
}

public extension DependencyValues {
  var chatInboxWatcher: @MainActor @Sendable (ChatAccessFolder) -> ChatInboxObservation {
    get { self[ChatInboxWatcherKey.self] }
    set { self[ChatInboxWatcherKey.self] = newValue }
  }

  var chatInboxFiles: ChatInboxFileClient {
    get { self[ChatInboxFilesKey.self] }
    set { self[ChatInboxFilesKey.self] = newValue }
  }

  var chatAccessContainer: ChatAccessContainerClient {
    get { self[ChatAccessContainerKey.self] }
    set { self[ChatAccessContainerKey.self] = newValue }
  }
}

private enum ChatAccessContainerKey: DependencyKey {
  static let liveValue = ChatAccessContainerClient.live(
    containerIdentifier: "iCloud.com.jonphillips.fithappens",
    isDevelopment: false,
    appName: "Fit Happens"
  )
}
