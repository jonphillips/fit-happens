import ChatAccessKit
import Dependencies
import Foundation
import LLMHandoffKit
import Observation
import Synchronization
import Testing

import FitHappensInboxKit

@MainActor
struct ChatInboxModelTests {
  private enum ClaimFailure: Error { case failed }

  private struct State: Sendable {
    var failedClaimURL: URL
    var alreadyClaimedURL: URL
    var claims: [URL] = []
  }

  @Test func applyClaimDiscardAndSwitchLifecycle() async {
    let defaults = UserDefaults.standard
    let oldEnabled = defaults.object(forKey: "fitHappensChatAccessEnabled")
    defer {
      if let oldEnabled {
        defaults.set(oldEnabled, forKey: "fitHappensChatAccessEnabled")
      } else {
        defaults.removeObject(forKey: "fitHappensChatAccessEnabled")
      }
    }
    defaults.set(false, forKey: "fitHappensChatAccessEnabled")

    let rows = (0..<4).map { index in
      let time = String(format: "%06d", 120_000 + index)
      let url = URL(fileURLWithPath: "/inbox/20261119T\(time)Z-program.fhprogram")
      return StagedProgramInboxRow(snapshot: ChatInboxSnapshot(
        url: url, name: url.lastPathComponent, isCurrent: true
      ))
    }
    let folder = ChatAccessFolder(containerURL: FileManager.default.temporaryDirectory, isDevelopment: false)
    let state = Mutex(State(failedClaimURL: rows[1].id, alreadyClaimedURL: rows[2].id))
    let (snapshots, continuation) = AsyncStream.makeStream(of: [ChatInboxSnapshot].self)
    let stopRecorder = WatcherStopRecorder()

    await withDependencies {
      $0.date = .constant(.now)
      $0.chatAccessContainer = .init(resolveFolder: { folder }, resolveAndCreateInbox: { folder })
      $0.chatInboxFiles = .init(
        read: { _ in "" },
        claim: { _, url, _ in
          let shouldFail = state.withLock { state in
            state.claims.append(url)
            return url == state.failedClaimURL
          }
          if shouldFail { throw ClaimFailure.failed }
          if url == rows[2].id { throw HandoffInboxError.alreadyClaimed }
        },
        maintain: { _, _, _ in }
      )
      $0.chatInboxWatcher = { _ in
        ChatInboxObservation(snapshots: snapshots, stop: { stopRecorder.stop() })
      }
    } operation: {
      let model = ChatInboxModel()
      defer { continuation.finish() }
      model.enabledChanged(true)
      await model.prepare()
      continuation.yield(rows.map(\.snapshot))
      await waitForRows(model, count: rows.count)

      var applyCalls = 0
      let rejectedApply = await model.applyStagedProgram(rows[0].id) {
        applyCalls += 1
        return false
      }
      #expect(!rejectedApply)
      #expect(applyCalls == 1)
      #expect(state.withLock { $0.claims.isEmpty })
      #expect(model.rows.contains(where: { $0.id == rows[0].id }))

      let successfulApply = await model.applyStagedProgram(rows[0].id) {
        applyCalls += 1
        return true
      }
      #expect(successfulApply)
      #expect(applyCalls == 2)
      #expect(!model.rows.contains(where: { $0.id == rows[0].id }))
      continuation.yield([rows[0].snapshot])
      await waitForRows(model, count: 0)
      #expect(!model.rows.contains(where: { $0.id == rows[0].id }))
      continuation.yield(rows.map(\.snapshot))
      await waitForRows(model, count: rows.count - 1)

      let appliedButUnclaimed = await model.applyStagedProgram(rows[1].id) { true }
      #expect(appliedButUnclaimed)
      #expect(model.rows.contains(where: { $0.id == rows[1].id }))
      #expect(model.rowErrors[rows[1].id] != nil)

      let claimedElsewhere = await model.applyStagedProgram(rows[2].id) { true }
      #expect(claimedElsewhere)
      #expect(!model.rows.contains(where: { $0.id == rows[2].id }))
      #expect(model.rowErrors[rows[2].id] == nil)

      let applyCallsBeforeDiscard = applyCalls
      await model.discard(rows[3])
      #expect(applyCalls == applyCallsBeforeDiscard)
      #expect(!model.rows.contains(where: { $0.id == rows[3].id }))
      #expect(state.withLock { $0.claims } == rows.map(\.id))

      model.enabledChanged(false)
      #expect(model.rows.isEmpty)
      #expect(stopRecorder.didStop)
      continuation.finish()
    }
  }

  private func waitForRows(_ model: ChatInboxModel, count: Int) async {
    while model.rows.count != count {
      await withCheckedContinuation { continuation in
        withObservationTracking { _ = model.rows.count } onChange: { continuation.resume() }
      }
    }
  }
}

@MainActor
private final class WatcherStopRecorder {
  private(set) var didStop = false

  func stop() { didStop = true }
}
