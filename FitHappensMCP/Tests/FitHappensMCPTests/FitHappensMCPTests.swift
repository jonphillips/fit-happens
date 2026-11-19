import Foundation
import MCPServerKit
import Testing
@testable import FitHappensMCPServer

struct FitHappensMCPTests {
  @Test func exposesTheThreeReadToolsAndReadsAnExport() async throws {
    let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let exports = home.appending(path: "Library/Mobile Documents/iCloud~com~jonphillips~fithappens/MCP/Exports")
    try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
    let data = Data("""
    {"version":1,"generatedAt":"2026-11-19T12:00:00Z","device":"iPhone","program":{"workouts":[{"key":"A","items":[{"exerciseKey":"bench","prescription":"3 × 5","name":"Bench","loadKind":"weight","currentWeight":145,"increment":5,"loadLabel":null,"notes":null}]}],"exercises":[{"key":"bench","name":"Bench","loadKind":"weight","currentWeight":145,"increment":5,"loadLabel":null,"notes":null}],"retiredExercises":[],"nextWorkoutKey":"A","lastCompletion":null},"completions":[],"walks":[],"bodyMass":[]}
    """.utf8)
    try data.write(to: exports.appending(path: "device.json"))
    let server = FitHappensMCPServer.make(home: home, now: { Date(timeIntervalSince1970: 1_795_000_000) })
    #expect(server.tools.map(\.name) == ["get_program", "get_history", "get_activity"])
    let result = try await server.tools[0].handler(.object([:]))
    #expect(result.content.first?.text.contains("145") == true)
    #expect(result.content.first?.text.contains("bench") == true)
  }

  @Test func reportsMissingExportAsToolError() async throws {
    let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(
      at: home.appending(path: "Library/Mobile Documents/iCloud~com~jonphillips~fithappens"),
      withIntermediateDirectories: true
    )
    let server = FitHappensMCPServer.make(home: home)
    await #expect(throws: Error.self) {
      _ = try await server.tools[0].handler(.object([:]))
    }
  }

  @Test func reportsNewerExportAsToolError() async throws {
    let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let exports = home.appending(path: "Library/Mobile Documents/iCloud~com~jonphillips~fithappens/MCP/Exports")
    try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
    let fixture = """
    {"version":2,"generatedAt":"2026-11-19T12:00:00Z","device":"iPhone","program":{"workouts":[],"exercises":[],"retiredExercises":[],"nextWorkoutKey":null,"lastCompletion":null},"completions":[],"walks":[],"bodyMass":[]}
    """
    try Data(fixture.utf8).write(to: exports.appending(path: "device.json"))
    let server = FitHappensMCPServer.make(home: home)
    await #expect(throws: Error.self) {
      _ = try await server.tools[0].handler(.object([:]))
    }
  }
}
