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

  @Test func getProgramIncludesRampAndProposalStagesValidRampButRejectsInvalidRamp() async throws {
    let rampExport = validExport().replacingOccurrences(
      of: "\"prescription\":\"3 × 5\"",
      with: "\"prescription\":\"10 @ 125 · 8 @ 135 · 6 @ 145\",\"ramp\":[{\"reps\":\"10\",\"offset\":-20},{\"reps\":\"8\",\"offset\":-10},{\"reps\":\"6\",\"offset\":0}]"
    )
    let home = try makeHome(with: rampExport)
    defer { try? FileManager.default.removeItem(at: home) }
    let server = FitHappensMCPServer.make(home: home)

    let program = try await call("get_program", on: server)
    #expect(!program.isError)
    #expect(program.text.contains("\"offset\":-20"))
    #expect(program.text.contains("10 @ 125 · 8 @ 135 · 6 @ 145"))

    let validRamp = """
    FH-PROGRAM: v1
    {"workouts":[{"key":"A","items":[{"key":"bench","name":"Bench","loadKind":"weight",
      "ramp":[{"reps":"10","offset":-25},{"reps":"8","offset":-10},{"reps":"6","offset":0}]}]}]}
    """
    let staged = try await call("propose_program", arguments: ["text": .string(validRamp)], on: server)
    #expect(!staged.isError)
    #expect(staged.text.contains("1 other change"))

    let invalidRamp = """
    FH-PROGRAM: v1
    {"workouts":[{"key":"A","items":[{"key":"bench","name":"Bench","loadKind":"weight",
      "ramp":[{"reps":"10","offset":1},{"reps":"6","offset":0}]}]}]}
    """
    let rejected = try await call("propose_program", arguments: ["text": .string(invalidRamp)], on: server)
    #expect(rejected.isError)
    #expect(rejected.text.contains("Ramp offsets for exercise bench must be finite and at or below 0."))
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

  @Test func stagesValidProposalAndRejectsInvalidProposalWithoutWriting() async throws {
    let home = try makeHome(with: validExport())
    defer { try? FileManager.default.removeItem(at: home) }
    let server = FitHappensMCPServer.make(home: home)
    let valid = """
    FH-PROGRAM: v1
    {"workouts":[{"key":"A","items":[{"key":"bench","name":"Bench","prescription":"3 × 5","loadKind":"weight","newWeight":150}]}]}
    """
    let response = try await call("propose_program", arguments: ["text": .string(valid)], on: server)
    #expect(!response.isError)
    #expect(response.text.contains("bench 145 → 150 lb"))
    #expect(response.text.contains("Review it in Fit Happens → Program."))

    let inbox = home.appending(path: "Library/Mobile Documents/iCloud~com~jonphillips~fithappens/MCP/Inbox")
    let staged = try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "fhprogram" }
    #expect(staged.count == 1)
    #expect(staged.first?.lastPathComponent.hasSuffix("-program.fhprogram") == true)
    #expect(try String(contentsOf: try #require(staged.first), encoding: .utf8) == valid)

    let invalid = try await call("propose_program", arguments: ["text": .string("FH-PROGRAM: v2\n{}")], on: server)
    #expect(invalid.isError)
    #expect(invalid.text.contains("Unsupported program marker"))
    let afterInvalid = try FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "fhprogram" }
    #expect(afterInvalid == staged)
  }

  @Test func stagesWithNoOrNewerExportUsingShapeValidationOnly() async throws {
    let home = try makeContainer()
    defer { try? FileManager.default.removeItem(at: home) }
    let text = """
    {"workouts":[{"key":"A","items":[{"key":"new","name":"New","prescription":"3 × 5","loadKind":"weight","startingWeight":10}]}]}
    """
    let response = try await call("propose_program", arguments: ["text": .string(text)], on: FitHappensMCPServer.make(home: home))
    #expect(!response.isError)
    #expect(response.text.contains("Review it in Fit Happens → Program."))
    #expect(!response.text.contains("changeSummary"))

    let newerHome = try makeHome(with: validExport(version: 2))
    defer { try? FileManager.default.removeItem(at: newerHome) }
    let newerResponse = try await call(
      "propose_program", arguments: ["text": .string(text)],
      on: FitHappensMCPServer.make(home: newerHome)
    )
    #expect(!newerResponse.isError)
    #expect(newerResponse.text.contains("Review it in Fit Happens → Program."))
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
