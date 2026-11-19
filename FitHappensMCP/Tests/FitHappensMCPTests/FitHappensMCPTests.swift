import FitHappensCore
import Foundation
import MCPServerKit
import Testing
@testable import FitHappensMCPServer

struct FitHappensMCPTests {
  @Test func readsProgramHistoryAndEmptyHealthThroughTheMCPHarness() async throws {
    let home = try makeHome(with: validExport())
    defer { try? FileManager.default.removeItem(at: home) }
    let server = FitHappensMCPServer.make(home: home, now: { Date(timeIntervalSince1970: 1_795_000_000) })

    let program = try await call("get_program", on: server)
    #expect(!program.isError)
    #expect(program.text.contains("145"))
    #expect(program.text.contains("bench"))

    let history = try await call("get_history", arguments: [
      "days": .integer(90), "exercise": .string("bench"),
    ], on: server)
    #expect(!history.isError)
    #expect(history.text.contains("loadChanges"))
    #expect(history.text.contains("\"pounds\":145"))
    #expect(history.text.contains("bench"))

    let activity = try await call("get_activity", on: server)
    #expect(!activity.isError)
    #expect(activity.text.contains("Nothing from Health yet."))
  }

  @Test func reportsNoExportYetThroughTheMCPHarness() async throws {
    let home = try makeContainer()
    defer { try? FileManager.default.removeItem(at: home) }
    let response = try await call("get_program", on: FitHappensMCPServer.make(home: home))
    #expect(response.isError)
    #expect(response.text.contains("No export yet."))
    #expect(!response.text.contains(home.path))
  }

  @Test func reportsANewerExportThroughTheMCPHarness() async throws {
    let home = try makeHome(with: validExport(version: 2))
    defer { try? FileManager.default.removeItem(at: home) }
    let response = try await call("get_program", on: FitHappensMCPServer.make(home: home))
    #expect(response.isError)
    #expect(response.text.contains("newer format"))
    #expect(!response.text.contains(home.path))
  }

  @Test func reportsMaterializationTimeoutThroughTheMCPHarness() async throws {
    let home = try makeHome(with: validExport())
    defer { try? FileManager.default.removeItem(at: home) }
    let server = FitHappensMCPServer.make(
      home: home,
      exportMaterializer: { _ in
        try await Task.sleep(for: .seconds(2))
        return Data()
      },
      materializationDeadline: .milliseconds(30)
    )
    let response = try await call("get_program", on: server)
    #expect(response.isError)
    #expect(response.text.contains("still downloading from iCloud"))
    #expect(!response.text.contains(home.path))
  }

  @Test func reportsMissingContainerWithoutLeakingItsPath() async throws {
    let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let response = try await call("get_program", on: FitHappensMCPServer.make(home: home))
    #expect(response.isError)
    #expect(response.text.contains("iCloud Drive folder isn't on this Mac yet"))
    #expect(!response.text.contains(home.path))
  }

  @Test func serverInstructionsHaveAStandaloneOpeningAndAppendTheContractVerbatim() throws {
    let instructions = try #require(FitHappensMCPServer.make().instructions)
    let opening = String(instructions.prefix(512))
    #expect(opening.contains("get_program"))
    #expect(opening.contains("propose_program"))
    #expect(opening.contains("FH-PROGRAM: v1"))
    #expect(instructions.hasSuffix(ProgramContractRules.instructions))
    #expect(MCPServer.instructionsHeadStandsAlone(instructions))
  }
}

private struct HarnessResult {
  var text: String
  var isError: Bool
}

private func call(
  _ name: String, arguments: [String: MCPValue] = [:], on server: MCPServer
) async throws -> HarnessResult {
  let request = MCPValue.object([
    "jsonrpc": .string("2.0"), "id": .integer(1), "method": .string("tools/call"),
    "params": .object(["name": .string(name), "arguments": .object(arguments)]),
  ])
  let line = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
  let response = try #require(await server.handle(line: line))
  let root = try #require(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
  let result = try #require(root["result"] as? [String: Any])
  let content = try #require(result["content"] as? [[String: Any]])
  let text = try #require(content.first?["text"] as? String)
  return HarnessResult(text: text, isError: result["isError"] as? Bool == true)
}

private func makeContainer() throws -> URL {
  let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  let container = home.appending(path: "Library/Mobile Documents/iCloud~com~jonphillips~fithappens")
  try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
  return home
}

private func makeHome(with export: String) throws -> URL {
  let home = try makeContainer()
  let exports = home.appending(path: "Library/Mobile Documents/iCloud~com~jonphillips~fithappens/MCP/Exports")
  try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
  try Data(export.utf8).write(to: exports.appending(path: "device.json"))
  return home
}

private func validExport(version: Int = 1) -> String {
  """
  {"version":\(version),"generatedAt":"2026-11-19T12:00:00Z","device":"iPhone","program":{"workouts":[{"key":"A","items":[{"exerciseKey":"bench","prescription":"3 × 5","name":"Bench","loadKind":"weight","currentWeight":145,"increment":5,"loadLabel":null,"notes":null}]}],"exercises":[{"key":"bench","name":"Bench","loadKind":"weight","currentWeight":145,"increment":5,"loadLabel":null,"notes":null}],"retiredExercises":[],"nextWorkoutKey":"A","lastCompletion":null},"completions":[{"date":"2026-09-20T12:00:00Z","workoutKey":"A","items":[{"exerciseKey":"bench","loadKind":"weight","loadPounds":135}]},{"date":"2026-11-10T12:00:00Z","workoutKey":"B","items":[{"exerciseKey":"bench","loadKind":"weight","loadPounds":145}]}],"walks":[],"bodyMass":[]}
  """
}
