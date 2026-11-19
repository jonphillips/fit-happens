import ChatAccessKit
import FitHappensCore
import Foundation
import MCPServerKit

private struct ExportSnapshot: Sendable {
  var value: FitHappensChatExport
  var ageMinutes: Int
}

private actor ExportStore {
  private let home: URL
  private let now: @Sendable () -> Date
  private let materializer: ChatAccessExportReader.Materializer?
  private let deadline: Duration
  private var reader: ChatAccessExportReader?

  init(
    home: URL, now: @escaping @Sendable () -> Date,
    materializer: ChatAccessExportReader.Materializer?, deadline: Duration
  ) {
    self.home = home
    self.now = now
    self.materializer = materializer
    self.deadline = deadline
  }

  func load() async throws -> ExportSnapshot {
    if reader == nil {
      let folder: ChatAccessFolder
      do {
        folder = try ChatAccessHelperFolder.existing(
          containerIdentifier: "iCloud.com.jonphillips.fithappens", isDevelopment: false, home: home
        )
      } catch {
        throw ToolError(
          "Fit Happens' iCloud Drive folder isn't on this Mac yet. Open Fit Happens, turn on Chat Access, and tap Refresh."
        )
      }
      reader = ChatAccessExportReader(folder: folder, materializationDeadline: deadline, materialize: materializer)
    }
    let file: ChatAccessExportFile
    do { file = try await reader!.readLatest() }
    catch ChatAccessExportReaderError.noExport {
      throw ToolError("No export yet. Open Fit Happens and tap Refresh in Program → Chat Access.")
    } catch ChatAccessExportReaderError.materializationTimedOut {
      throw ToolError("The Fit Happens export is still downloading from iCloud. Try again in a minute.")
    } catch {
      throw ToolError("The Fit Happens export could not be read. Open the app and tap Refresh in Program → Chat Access.")
    }
    let value: FitHappensChatExport
    do { value = try FitHappensChatExport.decode(file.data) }
    catch FitHappensChatExport.DecodeError.unsupportedVersion {
      throw ToolError("This Fit Happens export uses a newer format. Reinstall the Fit Happens helper.")
    } catch {
      throw ToolError("The Fit Happens export could not be read.")
    }
    return ExportSnapshot(value: value, ageMinutes: max(0, Int(now().timeIntervalSince(value.generatedAt) / 60)))
  }
}

private struct ToolError: LocalizedError {
  var errorDescription: String?
  init(_ message: String) { errorDescription = message }
}

private struct HistoryResult: Encodable {
  var generatedAt: Date
  var ageMinutes: Int
  var device: String
  var completions: [ChatCompletion]
  var loadChanges: [ChatLoadChange]
  var truncated: Bool
}

private struct ProgramResult: Encodable {
  var generatedAt: Date
  var ageMinutes: Int
  var device: String
  var program: ChatProgram
}

private struct ActivityResult: Encodable {
  var generatedAt: Date
  var ageMinutes: Int
  var device: String
  var walks: [ChatWalk]
  var bodyMass: [ChatBodyMass]
  var latestBodyMass: ChatBodyMass?
  var message: String?
  var truncated: Bool
}

public enum FitHappensMCPServer {
  public static func make(
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    now: @escaping @Sendable () -> Date = { Date() },
    exportMaterializer: ChatAccessExportReader.Materializer? = nil,
    materializationDeadline: Duration = .seconds(60)
  ) -> MCPServer {
    let store = ExportStore(home: home, now: now, materializer: exportMaterializer, deadline: materializationDeadline)
    return MCPServer(name: "fithappens", version: "0.1.0", instructions: ProgramContractRules.chatServerInstructions, tools: [
      tool("get_program", "Read the current program, exercise keys, weights, and next workout.", properties: [:], required: []) { _ in
        let snapshot = try await store.load()
        return .json(ProgramResult(
          generatedAt: snapshot.value.generatedAt, ageMinutes: snapshot.ageMinutes,
          device: snapshot.value.device, program: snapshot.value.program
        ))
      },
      tool("get_history", "Read workout history and the dates each exercise's prescribed load changed.", properties: [
        "days": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(365)]),
        "exercise": .object(["type": .string("string")]),
      ], required: []) { input in
        let snapshot = try await store.load()
        let days = input.objectValue?["days"].flatMap { if case let .integer(value) = $0 { value } else { nil } } ?? 90
        let exercise = input.objectValue?["exercise"]?.stringValue
        let history = FitHappensChatProjection.historyDetails(
          snapshot.value, days: days, exercise: exercise
        )
        let included = Array(history.completions.suffix(120))
        let includedChanges = Array(history.loadChanges.suffix(120))
        return .json(HistoryResult(
          generatedAt: snapshot.value.generatedAt, ageMinutes: snapshot.ageMinutes,
          device: snapshot.value.device, completions: included, loadChanges: includedChanges,
          truncated: history.completions.count > included.count
            || history.loadChanges.count > includedChanges.count
        ))
      },
      tool("get_activity", "Read walks and body weight from Apple Health.", properties: [
        "days": .object(["type": .string("integer"), "minimum": .integer(1), "maximum": .integer(365)]),
      ], required: []) { input in
        let snapshot = try await store.load()
        let days = input.objectValue?["days"].flatMap { if case let .integer(value) = $0 { value } else { nil } } ?? 90
        let activity = FitHappensChatProjection.activity(snapshot.value, days: days)
        return .json(ActivityResult(
          generatedAt: snapshot.value.generatedAt, ageMinutes: snapshot.ageMinutes,
          device: snapshot.value.device, walks: Array(activity.walks.suffix(120)),
          bodyMass: Array(activity.bodyMass.suffix(120)), latestBodyMass: activity.latestBodyMass,
          message: activity.walks.isEmpty && activity.bodyMass.isEmpty ? "Nothing from Health yet." : nil,
          truncated: activity.walks.count > 120 || activity.bodyMass.count > 120
        ))
      },
    ])
  }

  private static func tool(
    _ name: String, _ description: String, properties: [String: MCPValue], required: [String],
    handler: @escaping @Sendable (MCPValue) async throws -> MCPToolResult
  ) -> MCPTool {
    MCPTool(
      name: name, description: description,
      inputSchema: .object([
        "type": .string("object"), "properties": .object(properties),
        "required": .array(required.map(MCPValue.string)), "additionalProperties": .bool(false),
      ]), annotations: .init(readOnly: true, destructive: false, openWorld: false), handler: handler
    )
  }
}
